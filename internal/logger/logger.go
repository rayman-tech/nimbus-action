package logger

import (
	"log/slog"
	"os"
	"sync"
)

var logger *slog.Logger
var once sync.Once

func GetLogger() *slog.Logger {
	once.Do(func() {
		logger = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
			Level: slog.LevelDebug,
		}))
		slog.SetDefault(logger)
	})
	return logger
}
