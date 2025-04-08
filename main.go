package main

import (
	"image/png"
	"log"
	"os"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/ebitenutil"
)

type Game struct {
	x, y   float64
	player *ebiten.Image
}

func NewGame() *Game {
	img, err := loadPlayerImage("assets/player.png")

	if err != nil {
		log.Fatal("failed to load player image: %v", err)
	}
	return &Game{
		x:      100,
		y:      100,
		player: img,
	}
}

func loadPlayerImage(path string) (*ebiten.Image, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}

	defer f.Close()

	img, err := png.Decode(f)
	if err != nil {
		return nil, err
	}

	return ebiten.NewImageFromImage(img), nil
}

func (g *Game) Update() error {
	if ebiten.IsKeyPressed(ebiten.KeyW) {
		g.y -= 2
	}
	if ebiten.IsKeyPressed(ebiten.KeyS) {
		g.y += 2
	}
	if ebiten.IsKeyPressed(ebiten.KeyA) {
		g.x -= 2
	}
	if ebiten.IsKeyPressed(ebiten.KeyD) {
		g.x += 2
	}
	return nil
}

func (g *Game) Draw(screen *ebiten.Image) {
	ebitenutil.DebugPrint(screen, "Rodando Magic Survival...")

	op := &ebiten.DrawImageOptions{}
	op.GeoM.Scale(0.125, 0.125) // reduz 87.5% (256px -> 32px)
	op.GeoM.Translate(g.x, g.y)
	screen.DrawImage(g.player, op)

}

func (g *Game) Layout(outsideWidth, outsideHeight int) (screenWidth, screenHeight int) {
	return 640, 480
}

func main() {
	ebiten.SetWindowSize(640, 480)
	ebiten.SetWindowTitle("Magic Survival")
	game := NewGame()
	if err := ebiten.RunGame(game); err != nil {
		log.Fatal(err)
	}
}
