import base64;
import json;
import time;
import re;

import from crypto {
    def BIO_new_mem_buf(buf: bytes, length: i32) -> ptr;
    def BIO_free(bio: ptr) -> i32;
    def PEM_read_bio_PUBKEY(bio: ptr, key: ptr, cb: ptr, user: ptr) -> ptr;
    def EVP_PKEY_free(key: ptr);
    def EVP_MD_CTX_new -> ptr;
    def EVP_MD_CTX_free(ctx: ptr);
    def EVP_sha256 -> ptr;
    def EVP_DigestVerifyInit(ctx: ptr, pctx: ptr, md: ptr, engine: ptr, key: ptr) -> i32;
    def EVP_DigestVerify(ctx: ptr, sig: bytes, siglen: u64, data: bytes, length: u64) -> i32;
}

def decode_url(value: str) -> bytes;

def _der(tag: int, value: bytes) -> bytes;

def _integer(value: bytes) -> bytes;

def _public_pem(key: dict[str, any]) -> bytes;

def _verify_rs256(key: dict[str, any], signature: bytes, message: bytes) -> bool;

def validate_identity(
    token: str, jwks: dict[str, any], client_id: str, nonce: str, subject: str = "", at: int = -1
) -> dict[str, any];
