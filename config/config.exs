import Config

# Environment-specific overrides.
if File.exists?("config/#{config_env()}.exs") do
  import_config("#{config_env()}.exs")
end
