# VulnCommits

Ferramenta em Elixir que replica e estende o estudo de commits de correção de vulnerabilidade em projetos Elixir. Ela reaplica o filtro de palavras-chave do artigo (estágio 1), pede a um modelo de linguagem que julgue os candidatos (estágio 2) e compara o resultado com o rótulo humano do artigo (2012 a 2020) e com uma amostra rotulada à mão (2021 a 2025).

## Pré-requisitos

- Elixir 1.20 com OTP 29 (`mix --version`).
- `git` no PATH.
- Para falar com o GitHub: o `gh` autenticado (`gh auth login`) ou a variável `GITHUB_TOKEN`. Sem nenhum dos dois a consulta funciona, mas com limite menor de requisições.
- `ANTHROPIC_API_KEY`, só para `mix vuln.judge`. Nenhum outro comando usa a API da Anthropic.

As variáveis de ambiente não são lidas de arquivo. Copie `.env.example` para `.env`, preencha e carregue na sessão antes de rodar:

```sh
cp .env.example .env
set -a; source .env; set +a
mix deps.get
```

Todos os comandos abaixo rodam na raiz do projeto Mix (onde está o `mix.exs`).

## Pipeline

Cada etapa lê o que a anterior gravou. A ordem é esta:

```
mix vuln.dataset  ->  vuln.repos  ->  vuln.collect  ->  vuln.volume  ->  vuln.sample export
  ->  vuln.judge (dev 2012-2016, depois avaliação 2017-2020, depois estendido)
  ->  vuln.sample import  ->  vuln.report
```

| Comando | Lê | Grava |
|---|---|---|
| `mix vuln.dataset` | download do figshare (só se o arquivo não existe) | `data/figshare/ELIXIR_FINAL_SECURITY_BUG_DATASET.csv`; imprime o resumo do dataset |
| `mix vuln.repos` | o CSV do figshare, o GitHub e `priv/repo_map.exs` | clones em `repos/<nome>` e `data/repos.csv` (qual repositório segue ativo) |
| `mix vuln.collect` | `data/repos.csv`, o CSV do figshare e os clones | `data/commits.csv` (período original e estendido) e `data/repo_markers.csv` |
| `mix vuln.volume` | `data/repos.csv` e os clones | `data/volume.csv` (arquivos e linhas Elixir de cada commit da branch padrão, de 2012 a 2025) |
| `mix vuln.sample export` | `data/commits.csv`, `data/repos.csv` e os clones | `data/sample_80.csv`, a planilha de 80 commits para rotular à mão |
| `mix vuln.judge --period original --years 2012-2016` | `data/commits.csv`, os clones e a API da Anthropic | acrescenta linhas em `data/judgments.jsonl` (conjunto de desenvolvimento) |
| `mix vuln.judge --period original --years 2017-2020` | idem | idem (conjunto de avaliação) |
| `mix vuln.judge --period extended` | idem | idem (2021 a 2025) |
| `mix vuln.sample import` | `data/sample_80_labeled.csv`, `data/commits.csv` e `data/judgments.jsonl` | `out/manual_agreement.csv` |
| `mix vuln.report` | só `data/` | tabelas e `summary.json` em `out/` |

Observações:

- `vuln.judge` imprime o número de candidatos, de chamadas pendentes e o custo estimado antes de chamar a API. Use `--dry-run` para só ver isso. Acima de 200 chamadas ele exige `--yes`. Execuções repetidas pulam o que já foi julgado com o mesmo modelo e a mesma versão de prompt.
- O ajuste do prompt e a escolha do modelo só olham os candidatos de 2012 a 2016. A concordância reportada é a de 2017 a 2020. `mix vuln.report --dev` imprime só a concordância de 2012 a 2016.
- `data/sample_80_labeled.csv` é a cópia da planilha preenchida à mão. Sem ela, `vuln.report` apenas omite a linha da amostra manual.

## O que há em `data/` e `out/`

`data/` (entradas e resultados intermediários, versionados em git, menos os clones):

| Arquivo | Conteúdo |
|---|---|
| `figshare/ELIXIR_FINAL_SECURITY_BUG_DATASET.csv` | dataset do artigo: uma linha por par (commit, arquivo), com o rótulo humano |
| `repos.csv` | um repositório por linha: estrelas, se foi arquivado, branch padrão, hashes esperados e achados, commits Elixir em 2025 e 2026 e se segue ativo |
| `commits.csv` | um commit por linha, dos dois períodos (`original` e `extended`): data, ano, autor, `keyword_hit`, termos casados, `bot`, marcadores de IA, rótulo humano, arquivos e mensagem |
| `repo_markers.csv` | arquivos de instrução para agentes de IA (`AGENTS.md`, `CLAUDE.md` etc.) encontrados no histórico de cada repositório, com a data em que apareceram |
| `volume.csv` | um commit por linha, com todo o histórico da branch padrão dos repositórios ativos de 2012 a 2025 (sem merges, só commits com arquivo Elixir): data, e-mail do autor, `bot`, número de arquivos Elixir e linhas adicionadas e removidas neles (`git show --numstat -M`; arquivo renomeado só conta as linhas alteradas). De 2012 a 2020 são todos os commits, e não a amostra do dataset original; de 2021 a 2025 são os mesmos commits do período `extended` de `commits.csv`. Criado por `vuln.volume` |
| `sample_80.csv` | amostra estratificada de 80 commits do período estendido, com trecho do diff, para rotular à mão |
| `sample_80_labeled.csv` | a mesma planilha já rotulada (criada pelo autor, não pela ferramenta) |
| `judgments.jsonl` | um julgamento do modelo por linha (commit, execução 1 a 3, modelo, versão do prompt, rótulo, categoria CIA, motivo, uso de tokens ou erro). Criado por `vuln.judge` |

`out/` (gerado por `vuln.report`; cada tabela existe em `.tex` para o artigo e `.csv` para conferir):

| Arquivo | Conteúdo |
|---|---|
| `match.*` | comparação com os totais do artigo (commits, vulneráveis, proporção, repositórios, arquivos) |
| `per_year.*` | proporção de commits vulneráveis por ano, 2012 a 2025 |
| `agreement.*` | concordância modelo x humano (matriz de confusão, precisão, revocação, F1, kappa) e entre as 3 execuções |
| `ai_markers.*` | commits com e sem marcador de IA na mensagem, por ano (2021 a 2025) |
| `ai_repo_files.*` | arquivos de instrução de IA nos repositórios |
| `bots.*` | commits de bots por ano |
| `volume.*` | volume de alterações por ano (2012 a 2025, sem bots): commits, repositórios com commit no ano, autores distintos (por e-mail), arquivos Elixir alterados, arquivos por commit, commits com 10 arquivos ou mais, mediana de linhas adicionadas, total de linhas adicionadas e removidas e commits, arquivos e linhas adicionadas por autor |
| `volume_autores_frequentes.*` | autores com 10 commits ou mais no ano: quantos são, a parcela dos commits que fazem os commits, arquivos e linhas adicionadas por autor e a parcela de autores com um único commit no ano |
| `volume_repos.*`, `volume_trimestres.*`, `volume_sem_analytics.*` | as mesmas colunas por repositório e ano, por trimestre e sem o repositório `analytics` |
| `volume_vulneraveis.*` | commits vulneráveis por 10 mil linhas Elixir adicionadas, por ano |
| `tamanho_vulneraveis.*` | proporção de commits vulneráveis por número de arquivos Elixir no commit |
| `summary.json` | todos os números acima em um só arquivo, mais o modelo e a versão do prompt |
| `manual_agreement.csv` | kappa e matriz de confusão contra a amostra manual (criado por `vuln.sample import`) |

`repos/` guarda os clones (grandes) e `.env` guarda as chaves. Nenhum dos dois vai para o git.

## Reproduzir sem rede

`mix vuln.report` só lê arquivos de `data/` (`commits.csv`, `repo_markers.csv`, `judgments.jsonl` e, se existirem, `sample_80_labeled.csv` e `volume.csv`). Não usa rede, clones nem chave. Com os dados versionados, `mix deps.get && mix vuln.report` refaz todas as tabelas de `out/`. Se `judgments.jsonl` não existe, o comando avisa e trata todo candidato como neutro. Os testes (`mix test`) também rodam sem rede, com a API do GitHub e da Anthropic simuladas.

## Modelo e prompt

- Os julgamentos versionados em `data/judgments.jsonl` foram feitos por agentes do modelo `claude-opus-5-5`, pelo caminho `mix vuln.agents` (descrito abaixo). O mesmo modelo pode ser chamado pela API da Anthropic com `mix vuln.judge`. O nome do modelo gravado vem de `JUDGE_MODEL` (padrão `claude-opus-5-5`).
- Prompt: versão `v2`, em `priv/prompts/v2.md` (padrão). A `v1` foi a primeira tentativa e ficou guardada, com os julgamentos dela no conjunto de 2012 a 2016. Troque com `PROMPT_VERSION` (o arquivo `priv/prompts/<versão>.md` precisa existir).
- Cada candidato é julgado 3 vezes, em execuções independentes. O rótulo final é a maioria, com pelo menos 2 votos iguais. O diff vai truncado em 12.000 bytes, com prioridade para arquivos Elixir.
- `vuln.report` e `vuln.sample import` só usam os julgamentos do modelo e da versão de prompt vigentes.

### Julgamento por agentes (`mix vuln.agents`)

```sh
mix vuln.agents export --period original --years 2012-2016 --run 1 --out lotes/run1
# cada lotes/run1/batch-NNN.md é lido por um agente, que grava batch-NNN.out.jsonl
mix vuln.agents import --run 1 --out lotes/run1
```

`export` grava lotes de 20 commits, cada um com as instruções do prompt, a mensagem, os arquivos e o diff truncado. Cada lote é entregue a um agente novo, sem memória dos outros lotes nem das outras execuções, que devolve uma linha JSON por commit. `import` confere os hashes e acrescenta os julgamentos em `data/judgments.jsonl`. Por esse caminho não há controle de `temperature` nem de `seed`; a variação entre as 3 execuções é medida pelo kappa entre execuções em `out/agreement.*`.

### Julgamento pela API da Anthropic (`mix vuln.judge`)

Caminho alternativo, implementado e testado, mas não usado nos dados versionados: o mesmo modelo dos agentes (`claude-opus-5-5`, troque com `JUDGE_MODEL`), chamado pela Messages API com saída em JSON Schema (`output_config.format`) e `effort: "medium"`. O modelo não aceita `temperature` nem `seed`, então, como nos agentes, a variação entre as 3 execuções é medida e não fixada. Respostas 429 e 5xx são tentadas de novo até 5 vezes, com espera crescente.

## Regra do estágio 1 (palavras-chave)

A mensagem do commit é posta em minúsculas e separada em tokens (tudo que não é letra, dígito ou `_` vira separador). Um termo da lista de 48 do artigo casa quando seus tokens aparecem na mensagem, um logo após o outro, e cada token da mensagem é o token do termo, o token com um sufixo (`s`, `es`, `ed`, `d`, `ing`, `er`, `ers`) ou, para termos terminados em `e` ou `y`, a variante do radical (`race` casa `racing`, `violate` casa `violation`, `vulnerability` casa `vulnerabilities`). Termos compostos são tokens adjacentes: `gain access`, `cross site`, `request forgery` e `denial service`. Este último é literal, como está na lista do artigo, então a frase `denial of service` não casa. Um commit com pelo menos um termo casado tem `keyword_hit` e vira candidato ao estágio 2, desde que não seja de bot.
