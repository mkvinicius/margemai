# MargemAI

Assistente autônomo de CMV para pequenos negócios de alimentação.

Monitora custos, processa notas fiscais, detecta desvios e envia briefings diários via WhatsApp — sem intervenção manual.

## Instalação rápida (Ubuntu 22.04 / 24.04)

```bash
curl -fsSL https://raw.githubusercontent.com/mkvinicius/margemai/main/install.sh | bash
```

## Instalação manual

```bash
git clone https://github.com/mkvinicius/margemai
cd margemai
chmod +x install.sh
./install.sh
```

## Requisitos

- Ubuntu 22.04 ou 24.04
- 2 GB RAM mínimo
- 20 GB de disco disponível
- Chave da API Anthropic ([console.anthropic.com](https://console.anthropic.com/settings/keys))

## O que é instalado

| Componente | Versão | Função |
|------------|--------|--------|
| Node.js | 20 | Runtime do servidor Paperclip |
| pnpm | 9+ | Gerenciador de pacotes |
| Python | 3.11 | Runtime do Hermes |
| PostgreSQL | 15 | Banco de dados |
| PM2 | latest | Gerenciador de processos |

## Após a instalação

| URL | Descrição |
|-----|-----------|
| `http://localhost:3100` | Dashboard principal |
| `http://localhost:3100/cmv` | Dashboard CMV |

### Comandos úteis

```bash
# Status dos processos
pm2 list

# Logs em tempo real
pm2 logs margemai-server
pm2 logs margemai-hermes

# Reiniciar
pm2 restart all

# Parar
pm2 stop all
```

## Agentes CMV incluídos

- **Conselheiro de Lucro (CEO)** — Consolidação e briefing diário às 07h
- **Especialista CMV (CFO)** — Cálculo teórico vs. real, relatório semanal
- **Gestor de Compras** — Processamento de NF-e, alertas de preço
- **Ponto de Equilíbrio** — Break-even, simulações de custo e preço

## Estrutura do projeto

```
margemai/
├── paperclip/          # Plataforma de orquestração (TypeScript)
│   ├── server/         # API + servidor de agentes
│   ├── ui/             # Dashboard React
│   └── packages/db/    # Schema Drizzle + migrations
├── hermes/             # Framework de agentes (Python)
│   ├── skills/cmv/     # 6 skills de CMV
│   └── gateway/        # Gateway WhatsApp/Telegram
├── install.sh          # Instalador
└── pm2.config.js       # Gerado pelo instalador
```

## Atualização

```bash
git pull
git submodule update --recursive
./install.sh
```

O instalador é idempotente — rodar novamente atualiza o que mudou sem apagar dados.
