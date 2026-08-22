from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "sqlite:///./fieldos_dev.db"
    # Optional -- only voice-to-DPR needs this. Everything else is offline.
    sarvam_api_key: str = ""
    # Upload cap for documents/photos. A shared-install disk must not be
    # fillable by one oversized request.
    max_upload_mb: int = 25

    class Config:
        env_file = ".env"


settings = Settings()
