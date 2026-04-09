package store

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type DeviceRegistration struct {
	InstallationID string    `json:"installationId"`
	DeviceToken    string    `json:"deviceToken"`
	Topics         []string  `json:"topics"`
	Name           string    `json:"name,omitempty"`
	UpdatedAt      time.Time `json:"updatedAt"`
}

type Event struct {
	ID          string    `json:"id"`
	Topic       string    `json:"topic"`
	Title       string    `json:"title"`
	Message     string    `json:"message"`
	Source      string    `json:"source,omitempty"`
	Project     string    `json:"project,omitempty"`
	ThreadTitle string    `json:"threadTitle,omitempty"`
	CreatedAt   time.Time `json:"createdAt"`
}

type snapshot struct {
	Devices map[string]DeviceRegistration `json:"devices"`
	Events  []Event                       `json:"events"`
}

type Store struct {
	mu    sync.RWMutex
	path  string
	state snapshot
}

func New(path string) (*Store, error) {
	if strings.TrimSpace(path) == "" {
		return nil, errors.New("store path is required")
	}

	s := &Store{
		path: path,
		state: snapshot{
			Devices: map[string]DeviceRegistration{},
			Events:  []Event{},
		},
	}

	if err := s.load(); err != nil {
		return nil, err
	}

	return s, nil
}

func (s *Store) UpsertDevice(reg DeviceRegistration) (DeviceRegistration, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	reg.InstallationID = strings.TrimSpace(reg.InstallationID)
	reg.DeviceToken = strings.TrimSpace(reg.DeviceToken)
	reg.Name = strings.TrimSpace(reg.Name)
	reg.Topics = normalizeTopics(reg.Topics)
	reg.UpdatedAt = time.Now().UTC()

	s.state.Devices[reg.InstallationID] = reg
	return reg, s.persistLocked()
}

func (s *Store) DeleteDevice(installationID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	delete(s.state.Devices, installationID)
	return s.persistLocked()
}

func (s *Store) DeleteDeviceByToken(deviceToken string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	for installationID, reg := range s.state.Devices {
		if reg.DeviceToken == deviceToken {
			delete(s.state.Devices, installationID)
		}
	}

	return s.persistLocked()
}

func (s *Store) DevicesForTopic(topic string) []DeviceRegistration {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var matches []DeviceRegistration
	for _, reg := range s.state.Devices {
		for _, subscription := range reg.Topics {
			if subscription == topic {
				matches = append(matches, reg)
				break
			}
		}
	}

	sort.Slice(matches, func(i, j int) bool {
		return matches[i].UpdatedAt.After(matches[j].UpdatedAt)
	})

	return matches
}

func (s *Store) AddEvent(event Event, maxEvents int) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.state.Events = append(s.state.Events, event)
	if len(s.state.Events) > maxEvents {
		s.state.Events = append([]Event(nil), s.state.Events[len(s.state.Events)-maxEvents:]...)
	}

	return s.persistLocked()
}

func (s *Store) EventsForTopic(topic string, limit int) []Event {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if limit <= 0 {
		limit = 50
	}

	events := make([]Event, 0, limit)
	for i := len(s.state.Events) - 1; i >= 0 && len(events) < limit; i-- {
		event := s.state.Events[i]
		if event.Topic == topic {
			events = append(events, event)
		}
	}

	return events
}

func (s *Store) EventByID(eventID string) (Event, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for i := len(s.state.Events) - 1; i >= 0; i-- {
		event := s.state.Events[i]
		if event.ID == eventID {
			return event, true
		}
	}

	return Event{}, false
}

func (s *Store) load() error {
	data, err := os.ReadFile(s.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return s.persistSnapshot(s.state)
		}
		return err
	}

	if len(data) == 0 {
		return nil
	}

	var loaded snapshot
	if err := json.Unmarshal(data, &loaded); err != nil {
		return err
	}
	if loaded.Devices == nil {
		loaded.Devices = map[string]DeviceRegistration{}
	}
	if loaded.Events == nil {
		loaded.Events = []Event{}
	}

	s.state = loaded
	return nil
}

func (s *Store) persistLocked() error {
	return s.persistSnapshot(s.state)
}

func (s *Store) persistSnapshot(state snapshot) error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}

	payload, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}

	tempPath := s.path + ".tmp"
	if err := os.WriteFile(tempPath, payload, 0o600); err != nil {
		return err
	}

	return os.Rename(tempPath, s.path)
}

func normalizeTopics(topics []string) []string {
	seen := map[string]struct{}{}
	normalized := make([]string, 0, len(topics))

	for _, topic := range topics {
		cleaned := strings.TrimSpace(topic)
		if cleaned == "" {
			continue
		}
		if _, ok := seen[cleaned]; ok {
			continue
		}
		seen[cleaned] = struct{}{}
		normalized = append(normalized, cleaned)
	}

	sort.Strings(normalized)
	return normalized
}
