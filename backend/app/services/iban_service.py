"""
Minimal IBAN validation helpers for portal submissions.
"""
import re


class IbanService:
    @staticmethod
    def validate(iban: str) -> dict:
        compact = re.sub(r"\s+", "", iban or "").upper()
        if len(compact) < 15 or len(compact) > 34:
            return {"is_valid": False, "normalized_iban": compact, "reason": "invalid_length"}

        if not compact[:2].isalpha() or not compact[2:4].isdigit():
            return {"is_valid": False, "normalized_iban": compact, "reason": "invalid_format"}

        rearranged = compact[4:] + compact[:4]
        numeric = []
        for char in rearranged:
            if char.isdigit():
                numeric.append(char)
            elif char.isalpha():
                numeric.append(str(ord(char) - 55))
            else:
                return {"is_valid": False, "normalized_iban": compact, "reason": "invalid_characters"}

        remainder = 0
        for char in "".join(numeric):
            remainder = (remainder * 10 + int(char)) % 97

        result = {
            "is_valid": remainder == 1,
            "normalized_iban": compact,
            "country_code": compact[:2],
            "check_digits": compact[2:4],
        }

        if compact.startswith("IT") and len(compact) == 27:
            result.update(
                {
                    "cin": compact[4],
                    "abi": compact[5:10],
                    "cab": compact[10:15],
                    "account_number": compact[15:27],
                }
            )

        return result
