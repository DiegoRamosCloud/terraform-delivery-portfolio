# Ponte 8B - Repositorio publico e fluxo de entrega verificavel

Esta ponte acontece antes da etapa 9. Notificacoes continuam na etapa 9 e
self-service na etapa 10. Nome sugerido para o novo repositorio:
`terraform-delivery-portfolio`.

O objetivo e demonstrar controles funcionando, com PRs, falhas esperadas e
evidencias. Primeiro usamos Terraform sem cloud para validar o GitHub;
depois conectamos uma stack pequena AWS. Os comandos Git sao executados por voce.

## 1. Ajustes feitos e limites atuais

| Item da revisao | Entrega nesta ponte |
| --- | --- |
| OPA nao bloqueava `create_before_destroy` | Corrigido: qualquer acao `delete` e negada; regressao automatizada e novo Break |
| Permissao sem uso na etapa 1 | Removido `pull-requests: write` |
| Inputs interpolados no shell | Etapa 6 ajustada para `env` e argumentos entre aspas; modelo novo segue esse padrao |
| Arquivos locais `terraform.tfvars` | Removida excecao do `.gitignore`; exemplos devem usar `.tfvars.example` |
| PR ate apply com aprovacao | Template executavel com `terraform_data`, sem AWS |
| OPA apenas em fixtures | Template tambem avalia o JSON produzido por `terraform show` |
| Supply chain no modelo novo | Actions por SHA completo e Dependabot para Actions |
| Etapas antigas 3 a 5 com plan/apply no mesmo job | Permanecem como labs historicos; fluxo separado esta no template |
| Role de drift com escrita, bootstrap manual, scanners/lint completos | Pendentes nos incrementos AWS/seguranca descritos adiante |

Nao copiamos todos os workflows antigos para o publico. Existem exemplos
`wrong`/`break` intencionais, schedules e parametros especificos do lab privado.
Nao use a pasta pai do projeto: ela contem material de outros clientes.

A remocao de uma excecao do `.gitignore` nao remove arquivos ja rastreados.
Revise com `git ls-files '*.tfvars' '*.tfvars.json' '*.tfstate*'`.
Um arquivo sensivel ja publicado exige tratamento do vazamento e rotacao;
ignora-lo no proximo commit nao limpa o historico.

## 2. Salvar e verificar os ajustes no lab atual

Na pasta `test-pipeline-ci-cd-terraform`, confira primeiro a branch e o diff.
Parta da sua branch com a etapa 8 validada; se ela ja foi integrada, atualize
a `main` antes de iniciar esta branch.

```bash
git status
git diff
git switch -c fix/pre-stage-9-review
git add .github/workflows/00-policy-regression.yml \
  .github/workflows/01-right-terraform-plan.yml \
  .github/workflows/06-right-scanners-policy.yml \
  .github/workflows/06-break-policy-as-code.yml \
  .gitignore policies/opa scripts/test-policy-fixtures.sh \
  examples/06-plan-json docs/06-scanners-policy-as-code.md \
  docs/08b-repositorio-publico.md docs/00-roadmap.md \
  docs/troubleshooting.md README.md templates/public-repository
git diff --cached --stat
git diff --cached
git commit -m "fix: close destructive plan policy gap and add public lab guide"
git push -u origin fix/pre-stage-9-review
```

Abra o PR na interface. `00 Policy regression` deve ficar verde. Depois do
merge, execute `06 Break Lab - Scanners and policy` com
`dangerous_create_before_destroy_plan`: vermelho e o resultado esperado.
O motivo deve citar o endereco do recurso e a acao que inclui `delete`.

## 3. Criar um repositorio publico vazio

1. No GitHub, clique em **New repository**.
2. Owner: `DiegoRamosCloud`; nome: `terraform-delivery-portfolio`.
3. Descricao: `Terraform delivery with policy gates, protected deployments and reproducible security labs`.
4. Marque **Public**. Deixe README, `.gitignore` e licenca desmarcados por enquanto.
5. Clique em **Create repository**. Nao altere a visibilidade do lab privado.

Comecar vazio evita o conflito `fetch first` causado por um README criado
remotamente. Uma licenca pode ser escolhida depois por PR; publico nao significa
automaticamente licenciado como open source.

No GitHub Free, repositorios publicos permitem testar rulesets e required
reviewers de Environments. Verifique as opcoes exibidas na sua conta.
Fontes: [rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
e [deployments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

## 4. Preparar uma copia selecionada, sem historico privado

Estes comandos criam outra pasta. Se ela ja existir, pare e inspecione seu
conteudo antes de continuar. Nao use `git push --mirror` nem copie `.git`.

```bash
LAB=/home/diego/clients/projects/projeto-pipeline-plataform/pipeline/test-pipeline-ci-cd-terraform
PUBLIC_DIR=/home/diego/clients/projects/projeto-pipeline-plataform/pipeline/terraform-delivery-portfolio

mkdir "$PUBLIC_DIR"
cd "$PUBLIC_DIR"
cp -R "$LAB/templates/public-repository/." .
mkdir -p policies/opa scripts examples/06-plan-json docs
cp "$LAB"/policies/opa/*.rego policies/opa/
cp "$LAB/scripts/test-policy-fixtures.sh" scripts/
cp "$LAB"/examples/06-plan-json/*.json examples/06-plan-json/
cp "$LAB/docs/08b-repositorio-publico.md" docs/

git init -b main
git add .
git diff --cached --stat
git diff --cached
git ls-files
```

Revise o que sera publicado. O template nao precisa de secrets, state real,
tfvars pessoais ou ARNs. A revisao deve incluir arquivos ocultos em `.github/`.
Nenhum scanner consegue garantir sozinho a ausencia de dados confidenciais.

```bash
git commit -m "feat: bootstrap public Terraform delivery lab"
git remote add origin git@github.com:DiegoRamosCloud/terraform-delivery-portfolio.git
git push -u origin main
```

`Terraform CI` deve executar. `Terraform deploy demo` fica pulado porque
`ENABLE_DEMO_DEPLOY` ainda nao esta habilitada. Essa variavel e uma chave de
ativacao do exercicio, nao um controle de autorizacao.

## 5. Configurar Actions e seguranca basica

Em **Settings > Actions > General**:

1. Habilite Actions. Se escolher allowlist, permita as actions usadas:
   `actions/checkout`, `actions/upload-artifact`, `actions/download-artifact`,
   `hashicorp/setup-terraform`, `open-policy-agent/setup-opa`.
2. Em Workflow permissions, selecione token de leitura.
3. Deixe desmarcado **Allow GitHub Actions to create and approve pull requests**.
4. Exija aprovacao para workflows de todos os contribuidores externos, se
   a opcao estiver disponivel. Use runners hospedados pelo GitHub neste lab.

O YAML do template pede apenas `contents: read`; nao pede OIDC, secrets ou
permissao de escrita. A configuracao default do token nao impede que um YAML
solicite outras permissoes admitidas pelo repositorio: a revisao do YAML continua
necessaria. Aprovar execucao de fork nao torna seu codigo confiavel para AWS.

Em **Settings > Advanced Security** (ou **Code security**, conforme a interface),
confira dependency graph, Dependabot alerts, secret scanning e push protection.
Habilite os controles disponiveis e private vulnerability reporting para
receber relatos. Nunca teste usando uma credencial real.
[Disponibilidade de seguranca](https://docs.github.com/en/code-security/getting-started/github-security-features).

O Dependabot proposto abre PRs para atualizar SHAs de Actions. Ele nao atualiza
as strings de versao do Terraform/OPA dentro de `with`: essas versoes ainda
precisam de PR de manutencao. SHA fixa o codigo da action, nao todas as
dependencias que ela baixa durante a execucao.

## 6. Escolher modo individual ou revisao independente

| Controle | Individual: exercitar interface | Com outro colaborador: simular equipe |
| --- | --- | --- |
| PR obrigatorio | Sim | Sim |
| Aprovacoes obrigatorias de PR | 0 | 1 ou mais conforme politica |
| CODEOWNERS review obrigatorio | Desligado enquanto for o unico owner | Ligado, com outro owner elegivel |
| Reviewer de deployment | Voce | Outro colaborador |
| Prevent self-review | Desligado | Ligado |
| Bypass de ruleset/deployment | Nao habilitar como rotina | Desabilitado |

Voce nao pode aprovar seu proprio PR. Com `Prevent self-review`, quem iniciou
o deployment tambem nao pode aprova-lo. Para testar segregacao real, convide
outra pessoa em **Settings > Collaborators**, com permissao de escrita para
reviews de codigo. Use somente a demonstracao sem AWS durante esse treino.

O template tem `@DiegoRamosCloud` em `.github/CODEOWNERS`. Acrescente o segundo
colaborador nas linhas relevantes antes de exigir review de code owner:

```text
* @DiegoRamosCloud @COLABORADOR
/.github/ @DiegoRamosCloud @COLABORADOR
/policies/ @DiegoRamosCloud @COLABORADOR
/infra/ @DiegoRamosCloud @COLABORADOR
```

Substitua `COLABORADOR` pelo usuario real com acesso write. GitHub usa o
CODEOWNERS da branch base. A existencia do arquivo nao exige review sozinha;
a exigencia vem do ruleset. Proteja tambem o proprio CODEOWNERS.
[Referencia CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners).

## 7. Proteger a main com ruleset

Depois do primeiro `Terraform CI` verde, abra **Settings > Rules > Rulesets >
New ruleset > New branch ruleset**:

1. Nome: `protect-main`; Enforcement: **Active**; branch alvo: `main`.
2. Deixe a lista de bypass vazia.
3. Habilite **Restrict deletions** e **Block force pushes**.
4. Habilite **Require a pull request before merging**.
5. Configure reviews conforme a tabela anterior. No modo equipe, habilite
   **Dismiss stale pull request approvals when new commits are pushed** e
   **Require review from Code Owners**. Exija aprovacao do ultimo push por
   outra pessoa quando quiser testar esse controle adicional.
6. Habilite **Require conversation resolution before merging**.
7. Habilite **Require status checks to pass** e selecione `terraform-ci`,
   originado de GitHub Actions. Exija branch atualizada antes do merge.
8. Salve. Em **General > Pull Requests**, use squash merge; caso exija
   historico linear no ruleset, desative merge commits.

Nao habilite `Restrict updates` neste exercicio: ele tem outro objetivo e
pode impedir atualizacoes esperadas. Nao selecione o job `apply` como check
obrigatorio de PR: ele so existe depois do merge.

Se `terraform-ci` nao aparecer, confira se executou recentemente. Use o nome
do check exibido no PR, nao apenas o nome do arquivo YAML. O template nao usa
filtro `paths` no CI, evitando PRs presos em check obrigatorio que nunca iniciou.

Um required check identifica um status, nao prova sozinho que o workflow e
imutavel. Review de `.github/` e controle de quem altera policies fecham outra
parte do risco. Um administrador ainda pode mudar as configuracoes do repo;
registre esse limite de governanca no portfolio.

## 8. Criar Environment antes de ativar o deploy

Em **Settings > Environments > New environment**, crie exatamente `prod-demo`:

1. Habilite **Required reviewers** e escolha o reviewer.
2. Configure **Prevent self-review** conforme o modo escolhido.
3. Desmarque **Allow administrators to bypass configured protection rules**.
4. Em **Deployment branches and tags**, escolha **Selected branches and tags**.
5. Adicione uma regra de tipo **Branch** com nome exato `main`. Nao adicione tags.
6. Salve. Nao cadastre secrets AWS nesta fase.

A lista de reviewers nao exige que todos aprovem: uma aprovacao elegivel basta.
Um environment citado no YAML pode ser criado sem protecoes se nao existir;
por isso configure-o antes de habilitar o exercicio.
[Gestao de environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).

Agora va a **Settings > Secrets and variables > Actions > Variables** e
adicione a variavel de repositorio `ENABLE_DEMO_DEPLOY` com valor `true`.
Ela precisa ser de repositorio porque o job de plan nao usa environment.

## 9. Primeiro PR e deployment

```bash
git switch -c feat/release-v2
```

Edite o default de `revision` em `infra/main.tf`, de `v1` para `v2`.

```bash
terraform -chdir=infra fmt
git add infra/main.tf
git diff --cached
git commit -m "feat: demonstrate reviewed release v2"
git push -u origin feat/release-v2
```

1. Abra PR para `main`. O CI gera um plano especulativo e aplica OPA ao JSON real.
2. Confira checks, summary, conversa e revisao. No modo equipe, o colaborador aprova.
3. Faca squash merge. O workflow de deployment gera **outro plano**, do commit
   integrado, e publica seu summary antes de aguardar aprovacao.
4. Em Actions, abra `Terraform deploy demo`. O job `plan` deve estar verde e
   `apply` aguardando review. O reviewer abre o summary do plan, confere commit
   e mudancas, e escolhe **Review deployments > Approve and deploy**.
5. O apply baixa o plano dessa execucao e aplica `tfplan`, sem recalcula-lo.

O plano do PR e uma previsao; nao e promovido cegamente para `main`.
Merge, atualizacao da branch ou drift podem mudar o resultado. A aprovacao de
deployment se refere ao plano pos-merge que realmente sera aplicado.

Os jobs usam a mesma versao do Terraform. O artefato inclui run ID e tentativa;
nao busca um arquivo arbitrario pelo nome em outra execucao. A retencao e de um
dia. Se expirar ou se voce reexecutar apenas o job apply em outra tentativa,
gere um novo plano executando **Re-run all jobs** e aprove novamente.

Aqui os dados sao sinteticos e o state e local/efemero: cada runner novo tende
a criar `terraform_data.release`. Esse comportamento e esperado nesta fase.
Nao use esse backend para recursos AWS persistentes.

## 10. Testes negativos, causa e tratamento

| Teste | Como provocar com seguranca | Resultado e tratamento |
| --- | --- | --- |
| Push direto na main | Em checkout limpo, crie commit vazio na main e tente push | Servidor rejeita; mova o commit para uma branch e abra PR |
| Check vermelho | Em PR, mude revision para `invalida` | Validate/plan falha; merge bloqueado; corrija para `vN` |
| Formatacao | Desalinhe atribuicoes HCL no PR | fmt falha; execute fmt e envie novo commit |
| Review ausente | PR verde sem aprovacao, no modo equipe | Merge bloqueado; code owner revisa |
| Review invalidado | Depois da aprovacao, envie novo commit | Exige novo review com stale approvals habilitado |
| Conversa aberta | Reviewer abre thread e nao resolve | Merge bloqueado ate resolver |
| Apply sem aprovacao | Faca merge e nao aprove o Environment | Plan termina; apply fica aguardando |
| Rejeicao do deploy | Reviewer escolhe Reject | Apply nao executa; corrija a causa e gere nova execucao |
| Autoaprovacao | Autor tenta aprovar seu deployment com self-review bloqueado | Nao pode aprovar; usar reviewer independente |
| Branch nao permitida | Execute deploy demo via workflow_dispatch em uma branch de teste | Plan pode rodar; Environment deve rejeitar apply fora de main |
| Replacement | No lab original, execute `dangerous_create_before_destroy_plan` | OPA nega; analisar necessidade e excecao especifica |
| Fork externo | Abra PR de fork com mudanca inocua em README | Apenas CI sem cloud; eventual aprovacao de execucao nao e aprovacao de deploy |

Para o teste do push direto, use somente checkout limpo e commit vazio:

```bash
git switch main
git pull --ff-only origin main
git commit --allow-empty -m "test: direct main push must fail"
git push origin main
```

Se rejeitar, preserve o commit em uma branch e abra PR:

```bash
git switch -c test/direct-push-blocked
git push -u origin test/direct-push-blocked
```

Nao use force push para "corrigir" esse erro esperado. Se aceitar o push,
o teste encontrou ruleset inativo, alvo errado ou bypass: confira antes de
registrar o controle como validado.

Para o teste de Environment, publique uma branch a partir de main e selecione-a
em **Actions > Terraform deploy demo > Run workflow > Use workflow from**.
O workflow permite dispatch em branch de proposito: quem rejeita o apply e a
regra do Environment, fora do YAML. Nao altere secrets ou roles para esse teste.

Um apply so pulado por `if` nao prova enforcement do servidor. Registre a
mensagem do Environment. Se remover `environment` do YAML, o demo sem cloud
pode executar: na fase AWS, a trust exata deve impedir obter a role de apply.

## 11. Incremento seguinte: stack AWS real

Este incremento ainda nao esta implementado no template. Faca-o por PR depois
de registrar os testes anteriores. Comece com um SSM Parameter String contendo
somente uma revisao ficticia e com backend S3 exclusivo do portfolio.

```text
PR externo/interno -> fmt/validate/scanners/policies sem AWS
main revisada     -> plan AWS com role de plan -> OPA -> aprovacao -> apply
schedule main     -> role de drift -> relatorio, sem correcao automatica
```

Um plan AWS de PR exige um fluxo adicional para codigo confiavel. HCL e codigo
executavel: providers e data sources podem executar comandos e ler state.
Uma role read-only ainda pode vazar dados. Nao execute codigo de fork em
`pull_request_target` ou `workflow_run` com credenciais e nao baixe artefatos
de PR como se fossem planos confiaveis de deployment. O template evita essa
fronteira fazendo o PR sem AWS e o plano cloud somente apos revisao/merge.
[Uso seguro de Actions](https://docs.github.com/en/actions/reference/security/secure-use).

### 11.1 Bootstrap e separacao de identidade

Crie uma stack `bootstrap/` que gerencie backend, roles e policies como recursos,
com `for_each` por ambiente/funcao. Nao replique o OIDC provider se ele ja existe
na conta: referencie ou importe o existente. Use state separado do workload;
apos criar o bucket, migre o state local do bootstrap com backup e
`terraform init -migrate-state`.

| Role por ambiente | State | Lock `.tflock` | Recurso SSM |
| --- | --- | --- | --- |
| plan | GetObject no objeto exato | GetObject, PutObject, DeleteObject | Somente leitura necessaria ao provider |
| apply | GetObject, PutObject no objeto exato | GetObject, PutObject, DeleteObject | Leitura e escrita apenas no prefixo autorizado |
| drift | GetObject no objeto exato | GetObject, PutObject, DeleteObject | Somente leitura; sem PutParameter/DeleteParameter |

O S3 tambem exige ListBucket com escopo de prefixo apropriado. Permissao de
lock nao autoriza escrever o state. Evite `ReadOnlyAccess` de toda a conta;
algumas chamadas de listagem exigem `Resource: "*"`, outras permitem escopo.
Verifique cada API do provider. A role de apply normalmente nao precisa
de DeleteObject no state. Nenhuma role do workload deve poder alterar IAM.

Use SSE-S3, versionamento, public access block, TLS obrigatorio e
`use_lockfile=true`. Mantemos a decisao do lab de nao exigir KMS. Prefixo
exemplo: `portfolio/hml/ssm/terraform.tfstate`. `prod` usa outro state e roles.
[Backend S3](https://developer.hashicorp.com/terraform/language/backend/s3).

### 11.2 OIDC do repositorio novo

O novo repo tem outro ID. Nao reutilize o `sub` do lab privado nem use
`repo:DiegoRamosCloud*`. Inspecione somente `sub`, `aud`, repositorio, ref e
environment do token, usando o metodo de debug da etapa 2; nunca publique
o JWT completo ou credenciais temporarias.

Exemplo ilustrativo para a role de apply de hml, substituindo IDs pelo token real:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:DiegoRamosCloud@OWNER_ID/terraform-delivery-portfolio@REPO_ID:environment:hml"
      }
    }
  }]
}
```

Use environments separados `hml-plan`, `hml`, `hml-drift`, `prod-plan`, `prod`
e `prod-drift`, todos restritos a main; reviewers no apply. Cada um aponta para
sua role, sem fallback automatico para uma role mais poderosa. O claim com
environment nao inclui automaticamente a branch: e a deployment branch policy
que fecha essa restricao. OIDC nao vincula ao workflow apenas por incluir repo
e environment; customizacao com workflow reutilizavel fica para a plataforma.

O GitHub documenta o formato imutavel com IDs para repos novos; confirme o
claim emitido. [Referencia OIDC](https://docs.github.com/en/actions/reference/security/oidc).

### 11.3 Plano salvo com dados reais

Um plano binario e seu JSON podem conter dados sensiveis, mesmo com variaveis
`sensitive`. Em repo publico, nao publique planos reais em artifacts, logs,
comentarios ou summaries. O template publica o plano completo somente porque
usa dados sinteticos sem cloud.

Para AWS, armazene plano e JSON em prefixo S3 privado com SSE-S3, TTL curto
via lifecycle e IAM por execucao. Exiba somente resumo permitido: enderecos
sanitizados, acoes e contagens, sem valores. Registre commit, run, tentativa,
versao Terraform, lockfile e hash do plano. Vincule a aprovacao a esses dados.
O apply recebe exatamente o plano revisado da mesma execucao; nao replana
silenciosamente. Nao promova o plano binario de hml para prod: sao states distintos.
[Dados em planos](https://developer.hashicorp.com/terraform/cli/commands/plan#out-filename).

`concurrency` deve ser por stack/ambiente, com `cancel-in-progress: false` no
deploy; o lock protege o state enquanto comandos o usam. O plano nao mantem
um lock durante toda a espera humana. Se outro apply alterar o state, espere
`Saved plan is stale`: refaca plan/policy/aprovacao. Drift externo nem sempre
altera o serial do state; limite a idade dos planos e reavalie apos espera longa.

### 11.4 Testes AWS para aceitar esse incremento

- Role de plan/drift tenta escrever SSM de teste: AccessDenied esperado.
- Role de hml tenta state/recurso de prod: AccessDenied esperado.
- Job sem environment ou com environment errado tenta role de apply: STS nega.
- Backend errado ou sem permissao: falha de init/plan, nunca interpretada como sem drift.
- Segundo apply altera state apos plano salvo: stale plan e nova aprovacao.
- Dois deployments na mesma stack: observar concurrency e lock, sem `-lock=false`.
- Novo apply sem alteracao: nenhuma mudanca com state remoto persistente.

## 12. Backlog da revisao e evidencias para entrevistas

Implemente cada linha por um PR pequeno, antes de apresentar como concluida:

| Incremento | Evidencia de aceite |
| --- | --- |
| Scanners HCL e excecao SSE-S3 delimitada | S3 inseguro bloqueado; seguro aprovado; excecao com dono, motivo e revisao |
| actionlint e zizmor | YAML invalido e input direto em run bloqueados em PR; versoes fixadas |
| Terraform test e modulo remoto | Testes do contrato; consumo por ref fixa e PR de upgrade; `.terraform.lock.hcl` nao fixa modulos Git |
| Bootstrap IaC e role drift dedicada | Recursos IAM gerenciados por Terraform; teste negativo de escrita |
| Recuperacao de state | Runbook testado em sandbox com backup/versionamento, sem forcar unlock de processo ativo |
| Metricas operacionais | Duracao, falhas por gate, tempo aguardando aprovacao e drift em aberto |

O plano externo propoe renumerar as etapas; aqui incorporamos o conteudo como
incrementos e preservamos 9/notificacoes e 10/self-service.

Crie `docs/evidencias.md` com links, sem tokens, states ou dados de clientes:

```markdown
| Controle | PR/run | Resultado observado | Causa e tratamento | Data |
| --- | --- | --- | --- | --- |
| Required check | PREENCHER | PREENCHER | PREENCHER | PREENCHER |
| Environment approval | PREENCHER | PREENCHER | PREENCHER | PREENCHER |
| Branch rejeitada | PREENCHER | PREENCHER | PREENCHER | PREENCHER |
```

Para cada decisao, escreva um ADR curto com contexto, escolha, alternativa e
limite: SSE-S3 versus KMS; plano especulativo versus pos-merge; role por funcao;
state remoto; dados que podem aparecer em relatorio publico.

Uma demonstracao de entrevista pode seguir: abrir PR valido, mostrar um gate
falhando, explicar a correcao, fazer merge, revisar o plano e aprovar o deploy.
Mostre o que o servidor impede e explique o que ainda depende de revisao humana.
Marque no README quais incrementos sao executaveis, quais foram validados e
quais continuam planejados. Configurar um controle e testar seu bloqueio sao
evidencias diferentes.
