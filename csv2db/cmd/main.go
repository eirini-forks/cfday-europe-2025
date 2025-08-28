package main

import (
	"log"
	"os"

	"github.com/GoogleCloudPlatform/functions-framework-go/funcframework"
	"github.com/eirini-forks/cfday-europe-2025/csv2db"
	_ "github.com/lib/pq"
)

func main() {
	funcframework.RegisterEventFunction("/", csv2db.HandleEvent)
	// Use PORT environment variable, or default to 8080.
	port := "8080"
	if envPort := os.Getenv("PORT"); envPort != "" {
		port = envPort
	}

	if err := funcframework.Start(port); err != nil {
		log.Fatalf("funcframework.Start: %v\n", err)
	}
}
