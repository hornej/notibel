package httpapi

import (
	"crypto/subtle"
	"encoding/json"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/hornej/notibel/internal/config"
	"github.com/hornej/notibel/internal/notifier"
	"github.com/hornej/notibel/internal/store"
)

var (
	topicPattern        = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)
	eventPattern        = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)
	installationPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)
)

type Server struct {
	cfg     config.Config
	store   *store.Store
	service *notifier.Service
	logger  *log.Logger
}

func New(cfg config.Config, eventStore *store.Store, service *notifier.Service, logger *log.Logger) http.Handler {
	server := &Server{
		cfg:     cfg,
		store:   eventStore,
		service: service,
		logger:  logger,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", server.handleHealth)
	mux.HandleFunc("/v1/publish/", server.handlePublish)
	mux.HandleFunc("/v1/topics/", server.handleTopicEvents)
	mux.HandleFunc("/v1/events/", server.handleEvent)
	mux.HandleFunc("/v1/devices/", server.handleDevices)
	return server.logRequests(mux)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"ok":             true,
		"apnsConfigured": s.cfg.HasAPNS(),
	})
}

func (s *Server) handlePublish(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if !authorized(r, s.cfg.PublishToken) {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	topic := strings.TrimPrefix(r.URL.Path, "/v1/publish/")
	if !validTopic(topic) {
		writeError(w, http.StatusBadRequest, "invalid topic")
		return
	}

	var req notifier.PublishRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json body")
		return
	}

	result, err := s.service.Publish(r.Context(), topic, req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, result)
}

func (s *Server) handleTopicEvents(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if !authorized(r, s.cfg.AppToken) {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	topic, ok := topicFromEventsPath(r.URL.Path)
	if !ok || !validTopic(topic) {
		writeError(w, http.StatusNotFound, "not found")
		return
	}

	limit := 50
	if rawLimit := strings.TrimSpace(r.URL.Query().Get("limit")); rawLimit != "" {
		parsedLimit, err := strconv.Atoi(rawLimit)
		if err != nil || parsedLimit <= 0 {
			writeError(w, http.StatusBadRequest, "invalid limit")
			return
		}
		if parsedLimit > 200 {
			parsedLimit = 200
		}
		limit = parsedLimit
	}

	events := s.store.EventsForTopic(topic, limit)
	writeJSON(w, http.StatusOK, map[string]any{
		"topic":  topic,
		"events": events,
	})
}

func (s *Server) handleDevices(w http.ResponseWriter, r *http.Request) {
	if !authorized(r, s.cfg.AppToken) {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	installationID := strings.TrimPrefix(r.URL.Path, "/v1/devices/")
	if !validInstallationID(installationID) {
		writeError(w, http.StatusBadRequest, "invalid installation id")
		return
	}

	switch r.Method {
	case http.MethodPut:
		s.handleUpsertDevice(w, r, installationID)
	case http.MethodDelete:
		if err := s.store.DeleteDevice(installationID); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to delete device")
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":             true,
			"installationId": installationID,
		})
	default:
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func (s *Server) handleEvent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if !authorized(r, s.cfg.AppToken) {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	eventID, ok := eventIDFromPath(r.URL.Path)
	if !ok || !validEventID(eventID) {
		writeError(w, http.StatusNotFound, "not found")
		return
	}

	event, found := s.store.EventByID(eventID)
	if !found {
		writeError(w, http.StatusNotFound, "event not found")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"event": event,
	})
}

func (s *Server) handleUpsertDevice(w http.ResponseWriter, r *http.Request, installationID string) {
	var payload struct {
		DeviceToken string   `json:"deviceToken"`
		Topics      []string `json:"topics"`
		Name        string   `json:"name"`
	}

	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json body")
		return
	}
	if strings.TrimSpace(payload.DeviceToken) == "" {
		writeError(w, http.StatusBadRequest, "deviceToken is required")
		return
	}
	if len(payload.Topics) == 0 {
		writeError(w, http.StatusBadRequest, "topics must not be empty")
		return
	}

	registration, err := s.store.UpsertDevice(store.DeviceRegistration{
		InstallationID: installationID,
		DeviceToken:    payload.DeviceToken,
		Topics:         payload.Topics,
		Name:           payload.Name,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to save device")
		return
	}

	writeJSON(w, http.StatusOK, registration)
}

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.logger.Printf("%s %s", r.Method, r.URL.Path)
		next.ServeHTTP(w, r)
	})
}

func authorized(r *http.Request, expected string) bool {
	if expected == "" {
		return true
	}

	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(header, "Bearer ") {
		return false
	}

	received := strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
	return subtle.ConstantTimeCompare([]byte(received), []byte(expected)) == 1
}

func validTopic(topic string) bool {
	return topicPattern.MatchString(strings.TrimSpace(topic))
}

func validInstallationID(installationID string) bool {
	return installationPattern.MatchString(strings.TrimSpace(installationID))
}

func validEventID(eventID string) bool {
	return eventPattern.MatchString(strings.TrimSpace(eventID))
}

func topicFromEventsPath(path string) (string, bool) {
	trimmed := strings.Trim(strings.TrimPrefix(path, "/v1/topics/"), "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 2 || parts[1] != "events" {
		return "", false
	}
	return parts[0], true
}

func eventIDFromPath(path string) (string, bool) {
	trimmed := strings.Trim(strings.TrimPrefix(path, "/v1/events/"), "/")
	if trimmed == "" || strings.Contains(trimmed, "/") {
		return "", false
	}
	return trimmed, true
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
