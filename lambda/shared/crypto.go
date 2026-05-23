package shared

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"io"
)

// EncryptAES256GCM encrypts data using AES-256-GCM
func EncryptAES256GCM(plaintext string, key string) (string, error) {
	decodedKey, err := hex.DecodeString(key)
	if err != nil {
		return "", err
	}

	if len(decodedKey) != 32 {
		return "", errors.New("key must be 32 bytes (256 bits)")
	}

	block, err := aes.NewCipher(decodedKey)
	if err != nil {
		return "", err
	}

	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonce := make([]byte, aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}

	ciphertext := aead.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

// DecryptAES256GCM decrypts data using AES-256-GCM
func DecryptAES256GCM(ciphertext string, key string) (string, error) {
	decodedKey, err := hex.DecodeString(key)
	if err != nil {
		return "", err
	}

	if len(decodedKey) != 32 {
		return "", errors.New("key must be 32 bytes (256 bits)")
	}

	block, err := aes.NewCipher(decodedKey)
	if err != nil {
		return "", err
	}

	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	decodedCiphertext, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", err
	}

	nonceSize := aead.NonceSize()
	if len(decodedCiphertext) < nonceSize {
		return "", errors.New("ciphertext too short")
	}

	nonce, ciphertext2 := decodedCiphertext[:nonceSize], decodedCiphertext[nonceSize:]
	plaintext, err := aead.Open(nil, nonce, ciphertext2, nil)
	if err != nil {
		return "", err
	}

	return string(plaintext), nil
}

// GenerateEncryptionKey generates a random 32-byte key and returns it as hex string
func GenerateEncryptionKey() (string, error) {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return "", err
	}
	return hex.EncodeToString(key), nil
}
