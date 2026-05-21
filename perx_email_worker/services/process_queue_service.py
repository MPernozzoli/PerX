"""
Client for the general cloud process job queue.
"""
import logging
from typing import Any, Dict, List, Optional

import requests

logger = logging.getLogger(__name__)


class ProcessQueueService:
    def __init__(self, api_url: str, worker_id: str, shared_secret: str):
        self.api_url = api_url.rstrip("/")
        self.worker_id = worker_id
        self.shared_secret = shared_secret

    @property
    def _headers(self) -> Dict[str, str]:
        return {
            "X-PerX-Worker-Secret": self.shared_secret,
            "Content-Type": "application/json",
        }

    def claim_jobs(
        self,
        limit: int = 3,
        lease_seconds: int = 300,
        job_types: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        if not self.shared_secret:
            logger.warning("LOCAL_AI_WORKER_SHARED_SECRET is not configured; cannot claim process jobs")
            return []

        params: list[tuple[str, Any]] = [
            ("worker_id", self.worker_id),
            ("limit", limit),
            ("lease_seconds", lease_seconds),
        ]
        for job_type in job_types or []:
            params.append(("job_type", job_type))

        response = requests.get(
            f"{self.api_url}/api/v1/process-jobs/jobs/claim",
            params=params,
            headers=self._headers,
            timeout=30,
        )
        response.raise_for_status()
        return response.json().get("items", [])

    def heartbeat(self, job_id: str, lease_seconds: int = 300) -> Dict[str, Any]:
        response = requests.post(
            f"{self.api_url}/api/v1/process-jobs/jobs/{job_id}/heartbeat",
            params={"worker_id": self.worker_id},
            json={"lease_seconds": lease_seconds},
            headers=self._headers,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    def complete_job(self, job_id: str, result: Dict[str, Any]) -> Dict[str, Any]:
        response = requests.post(
            f"{self.api_url}/api/v1/process-jobs/jobs/{job_id}/complete",
            params={"worker_id": self.worker_id},
            json={"result_json": result},
            headers=self._headers,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    def fail_job(
        self,
        job_id: str,
        error: str,
        retry: bool = True,
        result: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        response = requests.post(
            f"{self.api_url}/api/v1/process-jobs/jobs/{job_id}/fail",
            params={"worker_id": self.worker_id},
            json={"error": error, "retry": retry, "result_json": result},
            headers=self._headers,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()
