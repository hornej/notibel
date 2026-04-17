package httpapi

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/hornej/notibel/internal/config"
	"github.com/hornej/notibel/internal/notifier"
	"github.com/hornej/notibel/internal/store"
)

var (
	topicPattern        = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)
	eventPattern        = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)
	installationPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)
)

const (
	maxPublishBodyBytes = 1 << 20
	maxDeviceBodyBytes  = 32 << 10
	maxTopicsPerDevice  = 32
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

	stats := s.store.Stats()
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":             true,
		"apnsConfigured": s.cfg.HasAPNS(),
		"deviceCount":    stats.DeviceCount,
		"eventCount":     stats.EventCount,
		"eventLimit":     s.cfg.EventLimit,
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
	if err := decodeJSONBody(w, r, &req, maxPublishBodyBytes); err != nil {
		writeDecodeError(w, err)
		return
	}

	result, err := s.service.Publish(r.Context(), topic, req)
	if err != nil {
		var validationErr *notifier.ValidationError
		if errors.As(err, &validationErr) {
			writeError(w, http.StatusBadRequest, validationErr.Error())
			return
		}

		s.logger.Printf("publish failed for topic %s: %v", topic, err)
		writeError(w, http.StatusInternalServerError, "failed to publish event")
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

	if err := decodeJSONBody(w, r, &payload, maxDeviceBodyBytes); err != nil {
		writeDecodeError(w, err)
		return
	}
	if strings.TrimSpace(payload.DeviceToken) == "" {
		writeError(w, http.StatusBadRequest, "deviceToken is required")
		return
	}
	if err := validateTopics(payload.Topics); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
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
		startedAt := time.Now()
		loggedWriter := &loggingResponseWriter{
			ResponseWriter: w,
			status:         http.StatusOK,
		}

		next.ServeHTTP(loggedWriter, r)

		s.logger.Printf(
			"%s %s status=%d bytes=%d duration=%s",
			r.Method,
			r.URL.Path,
			loggedWriter.status,
			loggedWriter.bytes,
			time.Since(startedAt).Round(time.Millisecond),
		)
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

type loggingResponseWriter struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (w *loggingResponseWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *loggingResponseWriter) Write(payload []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}

	written, err := w.ResponseWriter.Write(payload)
	w.bytes += written
	return written, err
}

func decodeJSONBody(w http.ResponseWriter, r *http.Request, destination any, maxBytes int64) error {
	if r.Body == nil {
		return errors.New("missing request body")
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxBytes)

	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()

	if err := decoder.Decode(destination); err != nil {
		return err
	}

	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		if err == nil {
			return errors.New("body must contain a single json object")
		}
		return err
	}

	return nil
}

func writeDecodeError(w http.ResponseWriter, err error) {
	var maxBytesError *http.MaxBytesError
	if errors.As(err, &maxBytesError) {
		writeError(w, http.StatusRequestEntityTooLarge, "request body too large")
		return
	}

	writeError(w, http.StatusBadRequest, "invalid json body")
}

func validateTopics(topics []string) error {
	if len(topics) == 0 {
		return errors.New("topics must not be empty")
	}
	if len(topics) > maxTopicsPerDevice {
		return errors.New("too many topics")
	}

	for _, topic := range topics {
		if !validTopic(topic) {
			return errors.New("invalid topic")
		}
	}

	return nil
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
