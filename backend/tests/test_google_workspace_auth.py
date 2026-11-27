from app.services.google_workspace_auth import (
    GOOGLE_WORKSPACE_SCOPES,
    open_google_tokens,
    seal_google_tokens,
)


def test_google_scopes_cover_mail_and_calendar():
    assert "https://www.googleapis.com/auth/gmail.modify" in GOOGLE_WORKSPACE_SCOPES
    assert "https://www.googleapis.com/auth/gmail.settings.basic" in GOOGLE_WORKSPACE_SCOPES
    assert "https://www.googleapis.com/auth/calendar.events" in GOOGLE_WORKSPACE_SCOPES
    assert "openid" in GOOGLE_WORKSPACE_SCOPES


def test_google_mailbox_token_roundtrip():
    sealed = seal_google_tokens(refresh_token="refresh-1", access_token="access-1")
    assert "refresh-1" not in sealed
    opened = open_google_tokens(sealed)
    assert opened["refresh_token"] == "refresh-1"
    assert opened["access_token"] == "access-1"
