from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "sqlite:///./fieldos_dev.db"
    # Optional -- only voice-to-DPR needs this. Everything else is offline.
    sarvam_api_key: str = ""

    class Config:
        env_file = ".env"


settings = Settings()
