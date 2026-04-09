package notifier

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log"
	"strings"
	"time"

	"github.com/hornej/notibel/internal/apns"
	"github.com/hornej/notibel/internal/store"
)

type PublishRequest struct {
	Title       string `json:"title"`
	Message     string `json:"message"`
	Source      string `json:"source"`
	Project     string `json:"project"`
	ThreadTitle string `json:"threadTitle"`
}

type PublishResult struct {
	Event             store.Event `json:"event"`
	RegisteredDevices int         `json:"registeredDevices"`
	Delivered         int         `json:"delivered"`
	APNSConfigured    bool        `json:"apnsConfigured"`
}

type Service struct {
	store      *store.Store
	apns       apns.Client
	logger     *log.Logger
	eventLimit int
}

func New(store *store.Store, apnsClient apns.Client, logger *log.Logger, eventLimit int) *Service {
	return &Service{
		store:      store,
		apns:       apnsClient,
		logger:     logger,
		eventLimit: eventLimit,
	}
}

func (s *Service) Publish(ctx context.Context, topic string, req PublishRequest) (PublishResult, error) {
	message := strings.TrimSpace(req.Message)
	if message == "" {
		return PublishResult{}, errors.New("message is required")
	}

	title := strings.TrimSpace(req.Title)
	if title == "" {
		title = "Notibel"
	}

	source := strings.TrimSpace(req.Source)
	project := strings.TrimSpace(req.Project)
	threadTitle := strings.TrimSpace(req.ThreadTitle)
	event := store.Event{
		ID:          newEventID(),
		Topic:       topic,
		Title:       title,
		Message:     message,
		Source:      source,
		Project:     project,
		ThreadTitle: threadTitle,
		CreatedAt:   time.Now().UTC(),
	}

	if err := s.store.AddEvent(event, s.eventLimit); err != nil {
		return PublishResult{}, err
	}

	devices := s.store.DevicesForTopic(topic)
	result := PublishResult{
		Event:             event,
		RegisteredDevices: len(devices),
		APNSConfigured:    s.apns != nil,
	}

	if s.apns == nil {
		return result, nil
	}

	for _, reg := range devices {
		if err := s.apns.Send(ctx, reg.DeviceToken, event); err != nil {
			var unregistered *apns.ErrUnregistered
			if errors.As(err, &unregistered) {
				s.logger.Printf("dropping unregistered device token for %s: %v", reg.InstallationID, err)
				if deleteErr := s.store.DeleteDeviceByToken(reg.DeviceToken); deleteErr != nil {
					s.logger.Printf("delete device token: %v", deleteErr)
				}
				continue
			}

			s.logger.Printf("apns delivery failed for %s: %v", reg.InstallationID, err)
			continue
		}

		result.Delivered++
	}

	return result, nil
}

func newEventID() string {
	var bytes [8]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return time.Now().UTC().Format("20060102150405")
	}

	return hex.EncodeToString(bytes[:])
}
