TF_DIR := infrastructure/terraform

.PHONY: init validate deploy trigger queries evidence destroy

init:
	terraform -chdir=$(TF_DIR) init

validate:
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	terraform -chdir=$(TF_DIR) validate
	python3 -m py_compile src/lambda_ingest/app.py src/glue/raw_to_curated.py scripts/run_athena_queries.py

deploy:
	./scripts/deploy.sh

trigger:
	./scripts/trigger_pipeline.sh

queries:
	python3 scripts/run_athena_queries.py

evidence:
	./scripts/collect_evidence.sh

destroy:
	terraform -chdir=$(TF_DIR) destroy
