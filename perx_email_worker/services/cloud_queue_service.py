"""
Client for the cloud email processing queue.

This is the bridge used by the local Mac mini AI daemon to claim jobs created
from Resend inbound webhooks and report processing results back to the backend.
"""
import logging
from typing import Any, Dict, List, Optional

import requests

logger = logging.getLogger(__name__)


class CloudQueueService:
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

    def claim_jobs(self, limit: int = 5, lease_seconds: int = 300) -> List[Dict[str, Any]]:
        if not self.shared_secret:
            logger.warning("LOCAL_AI_WORKER_SHARED_SECRET is not configured; cannot claim cloud jobs")
            return []

        response = requests.get(
            f"{self.api_url}/api/v1/email-processing/jobs/claim",
            params={
                "worker_id": self.worker_id,
                "limit": limit,
                "lease_seconds": lease_seconds,
            },
            headers=self._headers,
            timeout=30,
        )
        response.raise_for_status()
        return response.json().get("items", [])

    def complete_job(self, job_id: str, result: Dict[str, Any], email_id: Optional[str] = None) -> Dict[str, Any]:
        response = requests.post(
            f"{self.api_url}/api/v1/email-processing/jobs/{job_id}/complete",
            json={"email_id": email_id, "result_json": result},
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
            f"{self.api_url}/api/v1/email-processing/jobs/{job_id}/fail",
            json={"error": error, "retry": retry, "result_json": result},
            headers=self._headers,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()
