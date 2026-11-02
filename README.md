# to-do-list_nube_activity

API de tareas por hacer en Python (Flask), desplegada en AWS con Terraform y GitHub Actions:
EC2 + Security Groups + Key Pair + RDS (PostgreSQL). La app se instala sola con `user_data`
y cada release nuevo se despliega automáticamente.

## Endpoints

| Método | Ruta       | Descripción                                               |
|--------|------------|-----------------------------------------------------------|
| GET    | `/tasks`   | Lista todas las tareas                                    |
| POST   | `/tasks`   | Crea una tarea. Body: `{"title": "...", "done": false}`   |
| GET    | `/version` | Versión desplegada (variable de entorno `APP_VERSION`)    |
| GET    | `/health`  | Estado de la app y tipo de almacenamiento                 |

Si la variable `DATABASE_URL` está definida, las tareas se guardan en esa base de datos; si no, en memoria.

## Estructura

```
app/
  app.py                  # API
  tests/test_app.py       # Pruebas unitarias
  requirements.txt        # Dependencias de producción
  requirements-dev.txt    # + pytest
terraform/
  main.tf                 # EC2, Security Groups, Key Pair, RDS, backend S3, outputs
  user_data.sh.tpl        # Arranque: clona el repo, instala y levanta la app
.github/workflows/
  infra-apply.yml         # Botón: crea la infraestructura
  infra-destroy.yml       # Botón: destruye la infraestructura
  ci.yml                  # Pruebas en cada PR a main
  release.yml             # Tag v#.#.# -> release con zip -> deploy
  deploy.yml              # Descarga el zip del release en la EC2 y reinicia
```

## Correr localmente

```bash
cd app
python3 -m venv .venv && source .venv/bin/activate
pip install --upgrade pip && pip install -r requirements-dev.txt
pytest -v                 # pruebas
python app.py             # http://localhost:8000/tasks
```

## Configuración en GitHub (una sola vez)

1. El repositorio debe ser **público** (la EC2 lo clona al arrancar).
2. Crea una llave SSH solo para este proyecto:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/to-do-list -N ""
   ```
3. En **Settings → Secrets and variables → Actions** agrega:

   | Secret            | Valor                                             | ¿Cuándo?                    |
   |-------------------|---------------------------------------------------|-----------------------------|
   | `SSH_PUBLIC_KEY`  | contenido de `~/.ssh/to-do-list.pub`              | una vez                     |
   | `SSH_PRIVATE_KEY` | contenido de `~/.ssh/to-do-list`                  | una vez                     |
   | `GH_PAT`          | (opcional) token que puede escribir secrets       | una vez                     |
   | `AWS_ACCESS_KEY_ID`     | de *AWS Details* en Learner Lab             | **cada sandbox nuevo**      |
   | `AWS_SECRET_ACCESS_KEY` | de *AWS Details* en Learner Lab             | **cada sandbox nuevo**      |
   | `AWS_SESSION_TOKEN`     | de *AWS Details* en Learner Lab             | **cada sandbox nuevo**      |
   | `EC2_HOST`        | IP pública de la EC2                              | después de cada *Infra - apply* |

   `GH_PAT`: un *fine-grained personal access token* limitado a este repo con permiso
   **Secrets: Read and write**. Si existe, *Infra - apply* guarda la IP en `EC2_HOST` sola;
   si no, la copias a mano del resumen del workflow.
4. Protege `main` para que solo se integren PRs con pruebas en verde:
   **Settings → Branches → Add rule** (o *Rulesets*) para `main` →
   *Require a pull request before merging* + *Require status checks to pass* → check **`tests`**.

## Parte 1: infraestructura con un botón

- **Actions → Infra - apply → Run workflow**: crea (si no existe) el bucket S3
  `to-do-list-tfstate-<account-id>` para el estado, corre `terraform apply` y muestra la IP.
- **Actions → Infra - destroy → Run workflow** (escribe `destroy` para confirmar).

**¿Dónde vive el tfstate?** En S3, dentro de la misma cuenta del sandbox, con versionado y
bloqueo (`use_lockfile`). Así nunca se sube al repo. Cuando el sandbox se borra, el bucket se va
junto con la infraestructura, así que el siguiente *apply* empieza limpio. La alternativa es
HCP Terraform (HashiCorp), que guarda el estado fuera de AWS.

RDS tarda ~5-10 min en crearse y la app ~2 min más en arrancar.

## Parte 2: CI / CD

- **CI**: cada PR a `main` corre `pytest`. Con la regla del paso 4 no se puede integrar si falla.
- **Continuous Delivery**: al empujar un tag se corren las pruebas y se crea un release con el
  repo en zip (`to-do-list-api-v1.0.0.zip`):
  ```bash
  git tag v1.0.0
  git push origin v1.0.0
  ```
- **Continuous Deployment**: al terminar el release, `deploy.yml` descarga el zip, lo copia a la
  EC2 por SSH, lo descomprime en `/opt/to-do-list/releases/<tag>`, apunta `current` a esa
  versión, actualiza `APP_VERSION` y reinicia el servicio. Al final valida que `/version`
  responda el tag nuevo. También corre si publicas un release a mano, o con *Run workflow*.

## Validar

```bash
curl http://<EC2_HOST>:8000/version
curl -X POST http://<EC2_HOST>:8000/tasks -H "Content-Type: application/json" -d '{"title": "Aprender Terraform"}'
curl http://<EC2_HOST>:8000/tasks
curl http://<EC2_HOST>:8000/health   # "storage": "DatabaseStore" = está usando RDS
```

Si no responde, revisa la instancia:

```bash
ssh -i ~/.ssh/to-do-list ec2-user@<EC2_HOST>
sudo cat /var/log/user-data.log
sudo journalctl -u to-do-list -f
```

## Terraform desde tu máquina (opcional)

```bash
cd terraform
export TF_VAR_public_key="$(cat ~/.ssh/to-do-list.pub)"
terraform init \
  -backend-config="bucket=to-do-list-tfstate-<account-id>" \
  -backend-config="key=to-do-list/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"
terraform plan
```

> `terraform.tfstate` está en `.gitignore`: contiene la contraseña de RDS y el estado de la infraestructura.
