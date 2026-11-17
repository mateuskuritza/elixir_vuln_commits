import Config

config :vuln_commits, github_req_options: []

config :vuln_commits, openai_req_options: []

import_config "#{config_env()}.exs"
