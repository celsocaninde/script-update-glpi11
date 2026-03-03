# Script de Atualização do GLPI 11

Script bash para atualização automática do GLPI na linha de versão **11.x**, compatível com **AlmaLinux 10.1**.

## O que o script faz

1. Ativa o modo de manutenção do GLPI
2. Renomeia `/var/www/html/glpi` → `/var/www/html/glpi-old` (backup)
3. Detecta automaticamente a última versão 11.x via API do GitHub
4. Baixa e descompacta a nova versão
5. Preserva as pastas: `files/`, `config/`, `plugins/`, `marketplace/`
6. Aplica permissões conforme a documentação oficial do GLPI
7. Executa `php bin/console db:update` para migrar o banco de dados
8. Limpa o cache e desativa o modo de manutenção

## Requisitos

- AlmaLinux 10.1 (ou similar RHEL-based)
- Apache (`apache:apache`)
- PHP (com `bin/console` funcional)
- `rsync`, `curl`, `tar`
- `jq` **ou** `python3` (para parsear a API do GitHub)

```bash
sudo dnf install jq rsync -y
```

## Uso

```bash
sudo bash glpi-update.sh
```

> Nenhum argumento necessário — a versão mais recente da linha 11.x é detectada automaticamente.

## Reverter em caso de falha

```bash
sudo mv /var/www/html/glpi /var/www/html/glpi-failed
sudo mv /var/www/html/glpi-old /var/www/html/glpi
```

## Licença

Uso pessoal / interno.
