import Config

config :vuln_commits, github_req_options: [plug: {Req.Test, VulnCommits.GitHub}]
config :vuln_commits, openai_req_options: [plug: {Req.Test, VulnCommits.Judge.OpenAI}]
