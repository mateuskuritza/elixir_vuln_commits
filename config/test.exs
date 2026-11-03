import Config

# nos testes o github é um stub do Req.Test, sem rede
config :vuln_commits, github_req_options: [plug: {Req.Test, VulnCommits.GitHub}]
