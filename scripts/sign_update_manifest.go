//go:build ignore

// Signs raw HydraBox update-manifest bytes with an Ed25519 seed/private key.
package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"flag"
	"fmt"
	"os"
)

func main() {
	input := flag.String("input", "", "manifest to sign")
	output := flag.String("output", "", "detached signature destination")
	encodedKey := flag.String("private-key", "", "base64 Ed25519 seed or private key")
	flag.Parse()
	if *input == "" || *output == "" || *encodedKey == "" {
		fatal("input, output and private-key are required")
	}
	rawKey, err := base64.StdEncoding.DecodeString(*encodedKey)
	if err != nil {
		fatal("private key is not valid base64: %v", err)
	}
	var privateKey ed25519.PrivateKey
	switch len(rawKey) {
	case ed25519.SeedSize:
		privateKey = ed25519.NewKeyFromSeed(rawKey)
	case ed25519.PrivateKeySize:
		privateKey = ed25519.PrivateKey(rawKey)
	default:
		fatal("private key must decode to 32 or 64 bytes")
	}
	manifest, err := os.ReadFile(*input)
	if err != nil {
		fatal("read manifest: %v", err)
	}
	signature := ed25519.Sign(privateKey, manifest)
	if err := os.WriteFile(*output, signature, 0o600); err != nil {
		fatal("write signature: %v", err)
	}
}

func fatal(format string, arguments ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", arguments...)
	os.Exit(1)
}
