# 🔁 migrate-scheduler-jobs

Este projeto contém um script bash para migrar jobs do Google Cloud Scheduler entre projetos, mantendo configurações, headers, body, e políticas de retry. Ideal para ambientes com múltiplos projetos (como dev e prod).

---

## 🗂️ Estrutura do projeto

```bash
.
├── script_source_to_target.sh     # Script principal para migração de jobs entre projetos
├── schedulers.json                # Armazena os jobs extraídos no formato JSON


## ⚙️ Pré-requisitos

- Ter o SDK do Google Cloud (`gcloud`) instalado e autenticado.
- Ter o `jq` instalado para leitura de arquivos JSON.
- Permissões suficientes nos projetos de origem e destino (`Cloud Scheduler Admin`, `Service Account User`, `Permissão para listar e criar jobs`).

---

## 🚀 Como usar

### Passo 1️⃣: Configure os parâmetros do script

Abra o arquivo script_source_to_target.sh e defina:
```bash
  SOURCE_PROJECT=""
  DESTINATION_PROJECT=""
  SOURCE_LOCATION=""
  DESTINATION_LOCATION=""
```
### Passo 2️⃣: Execute o script

Execute o script:

```bash
  bash script_source_to_target.sh
```

Esse script irá:

- Buscar todos os jobs no projeto e região de origem.
- Perguntar se você deseja copiar cada job encontrado.
- Exportar o JSON do job original.
- SArmazenar uma cópia no arquivo `schedulers.json`.
- Gerar dinamicamente o comando para recriar o job no projeto de destino com:
URI,Método HTTP,Body (base64 decodificado),Headers HTTP, Retry policy, Timezone, Schedule, Descrição
- Pausar o job original após criação (e o novo, caso estivesse pausado).

---

## 💡 Funcionalidades adicionais

- Evita sobrescrever jobs existentes no projeto de destino.
- Valida JSON com jq antes de qualquer ação.
- Garante headers concatenados corretamente com um único --headers.
- Trata corretamente corpo em base64.
- Aplica configurações de retryConfig do job original.

## 🛡️ Segurança e confiabilidade

- O script exige confirmação antes de copiar cada job.
- Jobs existentes no destino são detectados e ignorados com aviso.
- Todos os jobs exportados são armazenados em schedulers.json.
- Os jobs originais são pausados para evitar execução duplicada.

---


## ℹ️ Observações

- O script atualmente suporta apenas jobs do tipo http.
- Certifique-se de revisar os headers e corpo dos jobs no schedulers.json antes de criar no destino.

---

## 📄 Exemplo de JSON exportado
```json
  {
    "name": "projects/meu-projeto-dev/locations/us-east1/jobs/job-de-exemplo",
    "schedule": "*/5 * * * *",
    "timeZone": "America/Sao_Paulo",
    "httpTarget": {
      "uri": "https://exemplo.com/processar",
      "httpMethod": "POST",
      "headers": {
        "Content-Type": "application/json"
      },
      "body": "eyJ0ZXN0IjogInZhbG9yIn0="
    }
  }
```
---

## ✅ Exemplo de execução

```bash
vim migrate_scheduler_jobs.sh  # Configure variáveis de ambiente
bash migrate_scheduler_jobs.sh
```