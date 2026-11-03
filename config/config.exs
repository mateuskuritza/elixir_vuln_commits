import Config

# opções extras do Req para as chamadas ao github (vazio em dev e prod)
config :vuln_commits, github_req_options: []

import_config "#{config_env()}.exs"
