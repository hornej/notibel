package main

import (
	"errors"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/hornej/notibel/internal/apns"
	"github.com/hornej/notibel/internal/config"
	"github.com/hornej/notibel/internal/httpapi"
	"github.com/hornej/notibel/internal/notifier"
	"github.com/hornej/notibel/internal/store"
)

func main() {
	logger := log.New(os.Stdout, "notibel ", log.LstdFlags|log.Lmsgprefix)

	cfg, err := config.Load()
	if err != nil {
		logger.Fatalf("load config: %v", err)
	}

	eventStore, err := store.New(cfg.StorePath)
	if err != nil {
		logger.Fatalf("open store: %v", err)
	}

	apnsClient, err := apns.NewFromConfig(cfg, logger)
	if err != nil {
		logger.Fatalf("configure apns: %v", err)
	}

	if apnsClient == nil {
		logger.Printf("starting without APNs delivery; configure NOTIBEL_APNS_* to enable push")
	}

	service := notifier.New(eventStore, apnsClient, logger, cfg.EventLimit)
	handler := httpapi.New(cfg, eventStore, service, logger)

	server := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}

	logger.Printf("listening on %s", cfg.ListenAddr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Fatalf("serve: %v", err)
	}
}
