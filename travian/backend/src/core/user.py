# pylint: disable=no-name-in-module, too-few-public-methods
from pydantic import BaseModel


class UserCreate(BaseModel):
    """Input required to create a new User"""

    email: str
    password: str


class UserAuth(BaseModel):
    """Input required to authenticate a returning user"""

    id: int
    uuid: str
    email: str
    password: bytes
    salt: bytes


class id(BaseModel):
    """current authenticated User data stored in the JWT Web Token"""

    id: int
    email: str
