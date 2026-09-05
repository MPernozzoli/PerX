"""
Base offline antifraud checks for photos uploaded through the insured portal.

Fully local (no external service, no extra credentials): EXIF/GPS extraction,
a sanity comparison against the claim's confirmed inspection location, and a
perceptual hash used to flag photos re-submitted for a different item/claim.
No verdict here blocks an upload — the result is attached to the document's
metadata for the perito to see, and the perito remains the one who decides.
"""
from __future__ import annotations

import io
import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

from PIL import ExifTags, Image
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.document import Document
from app.models.inspection import InspectionPreference

IMAGE_MIME_PREFIXES = ("image/",)
DUPLICATE_HAMMING_THRESHOLD = 4  # out of 64 bits — near-identical images
LOCATION_MISMATCH_KM = 5.0


@dataclass
class PhotoAntifraudResult:
    checked_at: str
    has_exif: bool
    gps: Optional[dict] = None
    taken_at: Optional[str] = None
    phash: Optional[str] = None
    distance_km_from_claim_location: Optional[float] = None
    duplicate_of_document_id: Optional[str] = None
    flags: list[str] = field(default_factory=list)
    risk_level: str = "low"

    def to_dict(self) -> dict:
        return {
            "checked_at": self.checked_at,
            "has_exif": self.has_exif,
            "gps": self.gps,
            "taken_at": self.taken_at,
            "phash": self.phash,
            "distance_km_from_claim_location": self.distance_km_from_claim_location,
            "duplicate_of_document_id": self.duplicate_of_document_id,
            "flags": self.flags,
            "risk_level": self.risk_level,
        }


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius_km = 6371.0
    lat1_rad, lat2_rad = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2) ** 2
    return radius_km * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _dms_to_decimal(dms, ref: str) -> Optional[float]:
    try:
        degrees, minutes, seconds = (float(part) for part in dms)
    except (TypeError, ValueError):
        return None
    value = degrees + minutes / 60 + seconds / 3600
    if ref in ("S", "W"):
        value = -value
    return value


def _extract_exif(image: Image.Image) -> tuple[Optional[dict], Optional[str]]:
    exif = image.getexif()
    if not exif:
        return None, None

    gps_ifd = exif.get_ifd(ExifTags.IFD.GPSInfo) if hasattr(ExifTags, "IFD") else None
    gps = None
    if gps_ifd:
        lat = _dms_to_decimal(gps_ifd.get(2), gps_ifd.get(1, "N"))
        lng = _dms_to_decimal(gps_ifd.get(4), gps_ifd.get(3, "E"))
        if lat is not None and lng is not None:
            gps = {"lat": lat, "lng": lng}

    taken_at = None
    exif_ifd = exif.get_ifd(ExifTags.IFD.Exif) if hasattr(ExifTags, "IFD") else None
    raw_taken_at = (exif_ifd or {}).get(36867) or exif.get(306)
    if isinstance(raw_taken_at, str):
        try:
            taken_at = datetime.strptime(raw_taken_at.strip(), "%Y:%m:%d %H:%M:%S").isoformat()
        except ValueError:
            taken_at = None

    return gps, taken_at


def _perceptual_hash(image: Image.Image) -> str:
    small = image.convert("L").resize((8, 8), Image.Resampling.LANCZOS)
    pixels = list(small.getdata())
    average = sum(pixels) / len(pixels)
    bits = "".join("1" if pixel >= average else "0" for pixel in pixels)
    return f"{int(bits, 2):016x}"


def _hamming_distance(hash_a: str, hash_b: str) -> int:
    try:
        return bin(int(hash_a, 16) ^ int(hash_b, 16)).count("1")
    except ValueError:
        return 64


class PhotoAntifraudService:
    @staticmethod
    def is_supported_image(mime_type: Optional[str]) -> bool:
        return bool(mime_type) and mime_type.lower().startswith(IMAGE_MIME_PREFIXES)

    @staticmethod
    async def evaluate(
        db: AsyncSession,
        *,
        tenant_id: str,
        claim_id: str,
        document_id: str,
        content: bytes,
        mime_type: Optional[str],
    ) -> Optional[dict]:
        if not PhotoAntifraudService.is_supported_image(mime_type):
            return None

        try:
            image = Image.open(io.BytesIO(content))
            image.load()
        except Exception:
            return None

        gps, taken_at = _extract_exif(image)
        phash = _perceptual_hash(image)

        result = PhotoAntifraudResult(
            checked_at=datetime.now(timezone.utc).isoformat(),
            has_exif=gps is not None or taken_at is not None,
            gps=gps,
            taken_at=taken_at,
            phash=phash,
        )
        if gps is None:
            result.flags.append("no_gps_metadata")

        claim_location = await PhotoAntifraudService._claim_location(db, tenant_id, claim_id)
        if gps and claim_location:
            distance = _haversine_km(gps["lat"], gps["lng"], claim_location[0], claim_location[1])
            result.distance_km_from_claim_location = round(distance, 2)
            if distance > LOCATION_MISMATCH_KM:
                result.flags.append("location_mismatch")

        duplicate_id = await PhotoAntifraudService._find_duplicate(
            db, tenant_id=tenant_id, claim_id=claim_id, document_id=document_id, phash=phash,
        )
        if duplicate_id:
            result.duplicate_of_document_id = duplicate_id
            result.flags.append("duplicate_image")

        if "duplicate_image" in result.flags or "location_mismatch" in result.flags:
            result.risk_level = "high"
        elif result.flags:
            result.risk_level = "medium"

        return result.to_dict()

    @staticmethod
    async def _claim_location(
        db: AsyncSession, tenant_id: str, claim_id: str
    ) -> Optional[tuple[float, float]]:
        result = await db.execute(
            select(InspectionPreference.latitude, InspectionPreference.longitude).where(
                InspectionPreference.tenant_id == tenant_id,
                InspectionPreference.claim_id == claim_id,
            )
        )
        row = result.first()
        if not row or row[0] is None or row[1] is None:
            return None
        return float(row[0]), float(row[1])

    @staticmethod
    async def _find_duplicate(
        db: AsyncSession, *, tenant_id: str, claim_id: str, document_id: str, phash: str
    ) -> Optional[str]:
        result = await db.execute(
            select(Document.id, Document.metadata_json).where(
                Document.tenant_id == tenant_id,
                Document.claim_id == claim_id,
                Document.id != document_id,
            )
        )
        for other_id, metadata in result.all():
            other_phash = ((metadata or {}).get("antifraud") or {}).get("phash")
            if other_phash and _hamming_distance(phash, other_phash) <= DUPLICATE_HAMMING_THRESHOLD:
                return other_id
        return None
