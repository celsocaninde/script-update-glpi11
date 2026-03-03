<div align="center">

<img src="https://raw.githubusercontent.com/glpi-project/glpi/main/pics/logos/glpi-logo.png" width="280" alt="GLPI Logo"/>

# 🚀 GLPI 11 — Auto Update Script

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green?style=for-the-badge&logo=gnubash&logoColor=white)](glpi-update.sh)
[![AlmaLinux](https://img.shields.io/badge/AlmaLinux-10.1-0F4266?style=for-the-badge&logo=almalinux&logoColor=white)](https://almalinux.org)
[![GLPI](https://img.shields.io/badge/GLPI-11.x-FF6B35?style=for-the-badge)](https://glpi-project.org)
[![GitHub](https://img.shields.io/badge/GitHub-Releases-181717?style=for-the-badge&logo=github)](https://github.com/glpi-project/glpi/releases)

> **Script bash inteligente que detecta, baixa e aplica automaticamente a última versão estável do GLPI 11.x — com backup seguro, permissões corretas e migração de banco de dados.**

---

</div>

## ✨ Funcionalidades

| # | O que faz | Detalhe |
|---|-----------|---------|
| 🔒 | **Modo de manutenção** | Ativa antes de qualquer alteração via `php console` |
| 📦 | **Backup automático** | Renomeia `glpi/` → `glpi-old/` antes de qualquer mudança |
| 🌐 | **Detecção automática** | Consulta a API do GitHub e pega a última versão **11.x estável** |
| ⬇️ | **Download inteligente** | Baixa apenas o `.tgz` oficial, sem Source Code archives |
| 📁 | **Preserva seus dados** | Copia `files/`, `config/`, `plugins/` e `marketplace/` do backup |
| 🔐 | **Permissões corretas** | Segue a **documentação oficial do GLPI** (root para código, apache para dados) |
| 🗄️ | **Migração do banco** | Executa `php bin/console db:update` automaticamente |
| 🧹 | **Limpeza e finalização** | Limpa cache, desativa manutenção e remove arquivos temporários |

---

## 📋 Pré-requisitos

**Sistema:** AlmaLinux 10.1 (ou qualquer RHEL-based)

```bash
# Instale as dependências necessárias
sudo dnf install jq rsync curl tar -y
```

| Dependência | Obrigatório | Função |
|-------------|:-----------:|--------|
| `curl` | ✅ | Download do arquivo e consulta à API do GitHub |
| `tar` | ✅ | Descompactação do GLPI |
| `php` | ✅ | Execução do console GLPI |
| `rsync` | ✅ | Cópia das pastas preservadas |
| `jq` | ⚠️ | Parse do JSON da API *(fallback: `python3`)* |

---

## 🚀 Como usar

### 1. Baixe o script

```bash
curl -O https://raw.githubusercontent.com/celsocaninde/script-update-glpi11/main/glpi-update.sh
```

### 2. Execute como root

```bash
sudo bash glpi-update.sh
```

**Só isso.** O script detecta, baixa e instala a última versão 11.x automaticamente.

---

## 🔄 Fluxo de execução

```
┌─────────────────────────────────────────────────────────────┐
│                  GLPI UPDATE SCRIPT - FLUXO                 │
└─────────────────────────────────────────────────────────────┘

  [1] Ativa modo de manutenção
       └─► php bin/console glpi:maintenance:enable

  [2] Backup da instalação atual
       └─► /var/www/html/glpi  ──►  /var/www/html/glpi-old

  [3] Detecta última versão 11.x
       └─► API: api.github.com/repos/glpi-project/glpi/releases
                  ↓
              filtra: tag começa com "11.", não é prerelease
                  ↓
              ex: 11.0.7

  [4] Download + Descompactação
       └─► glpi-11.0.7.tgz  ──►  /var/www/html/glpi/

  [5] Restauração dos dados pessoais
       └─► glpi-old/files/        ──►  glpi/files/
           glpi-old/config/       ──►  glpi/config/
           glpi-old/plugins/      ──►  glpi/plugins/
           glpi-old/marketplace/  ──►  glpi/marketplace/

  [6] Permissões (padrão GLPI Docs)
       └─► Código-fonte: root:root  |  644 / 755
           Dados:        apache:apache  |  640 / 750

  [7] Migração do banco de dados
       └─► php bin/console db:update --no-interaction

  [8] Finalização
       └─► cache:clear  →  maintenance:disable  →  rm /tmp/glpi-update
```

---

## 🔐 Política de Permissões

> Segue rigorosamente a [documentação oficial do GLPI](https://glpi-install.readthedocs.io/en/latest/install/index.html).

```bash
# Código-fonte → somente leitura pelo Apache
chown root:root  /var/www/html/glpi
chmod 755 (dirs) / 644 (files)

# Pastas de dados → Apache pode escrever
chown apache:apache  files/  config/  plugins/  marketplace/  public/
chmod 750 (dirs) / 640 (files)
```

---

## 🛡️ Segurança & Recuperação

### ⚠️ Se algo der errado

```bash
# Reverter manualmente para a versão anterior
sudo mv /var/www/html/glpi      /var/www/html/glpi-failed
sudo mv /var/www/html/glpi-old  /var/www/html/glpi
```

### 🗑️ Após validar a atualização

```bash
# Remover o backup quando tiver certeza que está tudo ok
sudo rm -rf /var/www/html/glpi-old
```

---

## 📂 Estrutura do repositório

```
script-update-glpi11/
│
├── glpi-update.sh    ← Script principal de atualização
└── README.md         ← Este arquivo
```

---

## 🌐 Links úteis

- 📖 [Documentação oficial GLPI](https://glpi-install.readthedocs.io)
- 🐙 [Releases do GLPI no GitHub](https://github.com/glpi-project/glpi/releases)
- 🐛 [Reportar problemas neste script](https://github.com/celsocaninde/script-update-glpi11/issues)

---

<div align="center">

Feito com ❤️ para a comunidade GLPI 🇧🇷

</div>
