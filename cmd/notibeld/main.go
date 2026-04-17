package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
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

	if cfg.PublishToken == "" {
		logger.Printf("warning: NOTIBEL_PUBLISH_TOKEN is unset; publish API authentication is disabled")
	}
	if cfg.AppToken == "" {
		logger.Printf("warning: NOTIBEL_APP_TOKEN is unset; app API authentication is disabled")
	}

	eventStore, err := store.New(cfg.StorePath, logger)
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
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	shutdownSignals, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		<-shutdownSignals.Done()
		logger.Printf("shutdown requested")

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := server.Shutdown(ctx); err != nil {
			logger.Printf("graceful shutdown failed: %v", err)
			_ = server.Close()
		}
	}()

	logger.Printf("listening on %s", cfg.ListenAddr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Fatalf("serve: %v", err)
	}
	logger.Printf("server stopped")
}
