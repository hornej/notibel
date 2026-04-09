package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	ListenAddr      string
	StorePath       string
	EventLimit      int
	PublishToken    string
	AppToken        string
	APNSKeyPath     string
	APNSKeyID       string
	APNSTeamID      string
	APNSBundleID    string
	APNSEnvironment string
}

func Load() (Config, error) {
	eventLimit, err := envInt("NOTIBEL_EVENT_LIMIT", 500)
	if err != nil {
		return Config{}, err
	}

	cfg := Config{
		ListenAddr:      envOr("NOTIBEL_LISTEN_ADDR", ":8787"),
		StorePath:       envOr("NOTIBEL_STORE_PATH", "data/store.json"),
		EventLimit:      eventLimit,
		PublishToken:    strings.TrimSpace(os.Getenv("NOTIBEL_PUBLISH_TOKEN")),
		AppToken:        strings.TrimSpace(os.Getenv("NOTIBEL_APP_TOKEN")),
		APNSKeyPath:     strings.TrimSpace(os.Getenv("NOTIBEL_APNS_KEY_PATH")),
		APNSKeyID:       strings.TrimSpace(os.Getenv("NOTIBEL_APNS_KEY_ID")),
		APNSTeamID:      strings.TrimSpace(os.Getenv("NOTIBEL_APNS_TEAM_ID")),
		APNSBundleID:    strings.TrimSpace(os.Getenv("NOTIBEL_APNS_BUNDLE_ID")),
		APNSEnvironment: strings.ToLower(envOr("NOTIBEL_APNS_ENV", "development")),
	}

	switch cfg.APNSEnvironment {
	case "development", "production":
	default:
		return Config{}, fmt.Errorf("NOTIBEL_APNS_ENV must be development or production")
	}

	return cfg, nil
}

func (c Config) HasAPNS() bool {
	return c.APNSKeyPath != "" || c.APNSKeyID != "" || c.APNSTeamID != "" || c.APNSBundleID != ""
}

func (c Config) APNSUsesProduction() bool {
	return c.APNSEnvironment == "production"
}

func envOr(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func envInt(key string, fallback int) (int, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("%s must be an integer: %w", key, err)
	}
	if parsed <= 0 {
		return 0, fmt.Errorf("%s must be greater than zero", key)
	}
	return parsed, nil
}
