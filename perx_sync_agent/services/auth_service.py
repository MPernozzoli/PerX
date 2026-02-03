from fastapi import Header, HTTPException, Request, status


def get_token(request: Request, x_api_key: str = Header(default=None, convert_underscores=False)) -> str:
    if not x_api_key:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="X-API-Key header missing")
    expected = getattr(getattr(request.app, "state", None), "settings", None)
    expected_token = getattr(expected, "api_token", None)
    if expected_token and x_api_key != expected_token:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid X-API-Key")
    return x_api_key

