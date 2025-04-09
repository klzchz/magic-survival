package main

import (
	"image/color"
	"image/png"
	"log"
	"os"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/ebitenutil"
)

const (
	screenWidth  = 640
	screenHeight = 480
	spriteWidth  = 16
	spriteHeight = 16
	gravity      = 0.5
	scale        = 0.125
)

type Ground struct {
	Y      float64
	Height float64
}

type Game struct {
	x, y       float64
	vy         float64
	idleImg    *ebiten.Image
	walkImg    *ebiten.Image
	currentImg *ebiten.Image
	isMoving   bool
	onGround   bool
	ground     Ground
}

func NewGame() *Game {
	idle, err := loadPlayerImage("assets/player_idle.png")
	if err != nil {
		log.Fatalf("failed to load idle image: %v", err)
	}
	walk, err := loadPlayerImage("assets/player_walk.png")
	if err != nil {
		log.Fatalf("failed to load player_walk image: %v", err)
	}

	groundY := 368.0 // ajuste manual baseado na imagem de fundo ou posição desejada

	return &Game{
		x:          100,
		y:          100,
		idleImg:    idle,
		walkImg:    walk,
		currentImg: idle,
		vy:         0,
		onGround:   false,
		ground: Ground{
			Y:      groundY,
			Height: 0,
		},
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
	g.isMoving = false
	// g.onGround = false

	if ebiten.IsKeyPressed(ebiten.KeyA) {
		g.x -= 2
		g.isMoving = true
	}
	if ebiten.IsKeyPressed(ebiten.KeyD) {
		g.x += 2
		g.isMoving = true
	}
	if ebiten.IsKeyPressed(ebiten.KeySpace) && g.onGround {
		g.vy = -8
		g.isMoving = true
		g.onGround = false
	}

	// Aplicar gravidade
	g.vy += gravity
	g.y += g.vy

	// Colisão com o chão visual do background
	if g.y+spriteHeight*scale >= g.ground.Y {
		g.y = g.ground.Y - spriteHeight*scale
		g.vy = 0
		g.onGround = true
	}

	// Impede sair pelas bordas
	if g.x < 0 {
		g.x = 0
	}
	if g.x > float64(screenWidth)-(spriteWidth*scale) {
		g.x = float64(screenWidth) - (spriteWidth * scale)
	}
	if g.y < 0 {
		g.y = 0
	}

	// Troca sprite
	if g.isMoving {
		g.currentImg = g.walkImg
	} else {
		g.currentImg = g.idleImg
	}

	return nil
}

func (g *Game) Draw(screen *ebiten.Image) {
	screen.Fill(color.RGBA{70, 118, 166, 255})
	ebitenutil.DebugPrint(screen, "Rodando Magic Survival...")

	// Desenha o player
	op := &ebiten.DrawImageOptions{}
	op.GeoM.Scale(scale, scale)
	op.GeoM.Translate(g.x, g.y)
	screen.DrawImage(g.currentImg, op)
}

func (g *Game) Layout(outsideWidth, outsideHeight int) (int, int) {
	return screenWidth, screenHeight
}

func main() {
	ebiten.SetWindowSize(screenWidth, screenHeight)
	ebiten.SetWindowTitle("Magic Survival")
	game := NewGame()
	if err := ebiten.RunGame(game); err != nil {
		log.Fatal(err)
	}
}
