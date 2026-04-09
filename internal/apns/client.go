package apns

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/hornej/notibel/internal/config"
	"github.com/hornej/notibel/internal/store"
	"github.com/sideshow/apns2"
	"github.com/sideshow/apns2/token"
)

type Client interface {
	Send(ctx context.Context, deviceToken string, event store.Event) error
}

type ErrUnregistered struct {
	Reason string
}

func (e *ErrUnregistered) Error() string {
	return "apns token is no longer valid: " + e.Reason
}

type PushClient struct {
	client   *apns2.Client
	bundleID string
	logger   *log.Logger
}

func NewFromConfig(cfg config.Config, logger *log.Logger) (Client, error) {
	if !cfg.HasAPNS() {
		return nil, nil
	}

	missing := make([]string, 0, 4)
	if cfg.APNSKeyPath == "" {
		missing = append(missing, "NOTIBEL_APNS_KEY_PATH")
	}
	if cfg.APNSKeyID == "" {
		missing = append(missing, "NOTIBEL_APNS_KEY_ID")
	}
	if cfg.APNSTeamID == "" {
		missing = append(missing, "NOTIBEL_APNS_TEAM_ID")
	}
	if cfg.APNSBundleID == "" {
		missing = append(missing, "NOTIBEL_APNS_BUNDLE_ID")
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("incomplete APNS config: %s", strings.Join(missing, ", "))
	}

	authKey, err := token.AuthKeyFromFile(cfg.APNSKeyPath)
	if err != nil {
		return nil, fmt.Errorf("load apns key: %w", err)
	}

	authToken := &token.Token{
		AuthKey: authKey,
		KeyID:   cfg.APNSKeyID,
		TeamID:  cfg.APNSTeamID,
	}

	client := apns2.NewTokenClient(authToken)
	if cfg.APNSUsesProduction() {
		client = client.Production()
	} else {
		client = client.Development()
	}

	return &PushClient{
		client:   client,
		bundleID: cfg.APNSBundleID,
		logger:   logger,
	}, nil
}

func alertBody(message string) string {
	const maxRunes = 240

	message = strings.TrimSpace(message)
	if message == "" {
		return "Open Notibel to view the latest response."
	}

	if utf8.RuneCountInString(message) <= maxRunes {
		return message
	}

	runes := []rune(message)
	return string(runes[:maxRunes]) + "..."
}

func (c *PushClient) Send(ctx context.Context, deviceToken string, event store.Event) error {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	payload := map[string]any{
		"aps": map[string]any{
			"alert": map[string]any{
				"title": event.Title,
				"body":  alertBody(event.Message),
			},
			"sound":     "default",
			"thread-id": event.Topic,
		},
		"notibel": map[string]any{
			"event_id":     event.ID,
			"topic":        event.Topic,
			"source":       event.Source,
			"project":      event.Project,
			"thread_title": event.ThreadTitle,
			"created_at":   event.CreatedAt.Format(time.RFC3339),
		},
	}

	encodedPayload, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("encode apns payload: %w", err)
	}

	notification := &apns2.Notification{
		DeviceToken: strings.TrimSpace(deviceToken),
		Topic:       c.bundleID,
		Payload:     encodedPayload,
		PushType:    apns2.PushTypeAlert,
		Priority:    apns2.PriorityHigh,
	}

	response, err := c.client.PushWithContext(ctx, notification)
	if err != nil {
		return err
	}

	if response.StatusCode >= 200 && response.StatusCode < 300 {
		return nil
	}

	switch response.Reason {
	case "BadDeviceToken", "Unregistered":
		return &ErrUnregistered{Reason: response.Reason}
	}

	c.logger.Printf("apns returned status=%d reason=%s apns-id=%s", response.StatusCode, response.Reason, response.ApnsID)
	return fmt.Errorf("apns returned status %d: %s", response.StatusCode, response.Reason)
}
