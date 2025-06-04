package main

import (
	"path/filepath"
	"testing"
)

func TestLoadPlayerImageNotExist(t *testing.T) {
	_, err := loadPlayerImage(filepath.Join("assets", "does_not_exist.png"))
	if err == nil {
		t.Fatal("expected error when loading nonexistent image")
	}
}

func TestLoadPlayerImageExists(t *testing.T) {
	img, err := loadPlayerImage(filepath.Join("assets", "player.png"))
	if err != nil {
		t.Fatalf("unexpected error loading existing image: %v", err)
	}
	if img == nil {
		t.Fatal("expected non-nil image")
	}
}
