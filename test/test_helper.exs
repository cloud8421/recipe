# Configure logger console backend to output bare messages,
# no color (makes testing much easier)
logger_console_opts = [colors: [enabled: false],
                       format: "[$level] $message\n"]

Logger.configure_backend(:console, logger_console_opts)

ExUnit.start()
