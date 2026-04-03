package main

import (
	"context"
	"fmt"
	"path"
)

// DocumentConverter defines the interface for document transformation
type DocumentConverter interface {
	Convert(ctx context.Context, inputPath string) (*ConversionResult, error)
}

type ConversionResult struct {
	Data     []byte
	Metadata map[string]string
}

// PdfConverter implements DocumentConverter for PDF files
type PdfConverter struct {
	Config map[string]interface{}
}

func (p *PdfConverter) Convert(ctx context.Context, inputPath string) (*ConversionResult, error) {
	fmt.Printf("Converting PDF: %s\n", inputPath)
	if path.Ext(inputPath) != ".pdf" {
		return nil, fmt.Errorf("invalid file type")
	}
	return &ConversionResult{
		Data: []byte("pdf data"),
		Metadata: map[string]string{"type": "pdf"},
	}, nil
}

func main() {
	fmt.Println("Polyglot Go Test Asset")
}
