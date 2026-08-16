TEAM      := B6FVY827P9
CONTAINER := iCloud.net.kodare.Tada
# The checked-in source of truth. CloudKit will happily infer a schema from whatever records
# happen to get written, which silently omits any field that has only ever been nil — that is how
# completionTime and startedTime went missing. Declare the schema here instead.
SCHEMA    := cloudkit/schema.ckdb

.PHONY: help cloudkit-import-schema cloudkit-development-schema cloudkit-production-schema cloudkit-diff cloudkit-deploy-schema

help:
	@echo "CloudKit schema ($(SCHEMA) is the source of truth):"
	@echo "  make cloudkit-import-schema      Apply the schema file to development"
	@echo "  make cloudkit-development-schema Print the live development schema"
	@echo "  make cloudkit-production-schema  Print the live production schema"
	@echo "  make cloudkit-diff               Diff the schema file against production"
	@echo "  make cloudkit-deploy-schema      Apply to development, then deploy from the Console"
	@echo
	@echo "Physical devices use the production database, simulators use development, so a"
	@echo "schema change must be deployed to production before testing it on a device."
	@echo
	@echo "All of these need a CloudKit management token once per machine:"
	@echo "  create one at https://icloud.developer.apple.com/dashboard/ under"
	@echo "  Settings > Tokens > Management Tokens, then run:"
	@echo "  xcrun cktool save-token <token> --type management"

# Import replaces the whole schema, so the file must stay complete: leaving a record type out
# reads as a delete and CloudKit refuses ("invalid attempt to delete cloudkit managed record type").
cloudkit-import-schema:
	xcrun cktool import-schema --team-id $(TEAM) --container-id $(CONTAINER) \
		--environment development --file $(SCHEMA)

cloudkit-development-schema:
	@xcrun cktool export-schema --team-id $(TEAM) --container-id $(CONTAINER) \
		--environment development

cloudkit-production-schema:
	@xcrun cktool export-schema --team-id $(TEAM) --container-id $(CONTAINER) \
		--environment production

EXPORT_PRODUCTION = xcrun cktool export-schema --team-id $(TEAM) --container-id $(CONTAINER) \
	--environment production --output-file $(SCHEMA).production
OPEN := open

cloudkit-diff:
	@$(EXPORT_PRODUCTION)
	@if diff -u $(SCHEMA).production $(SCHEMA); then \
		echo "production matches $(SCHEMA)"; \
	else \
		echo; \
		echo "the + lines above are missing from production; deploying adds them permanently"; \
	fi; \
	rm -f $(SCHEMA).production

# cktool can only write to development: import-schema and validate-schema both reject production
# with "endpoint not applicable in the environment 'production'". Promoting development to
# production is Console-only, so this readies development and hands over — but only when there is
# actually something to deploy.
cloudkit-deploy-schema: cloudkit-import-schema
	@$(EXPORT_PRODUCTION)
	@if diff -u $(SCHEMA).production $(SCHEMA) > /dev/null 2>&1; then \
		rm -f $(SCHEMA).production; \
		echo "production already matches $(SCHEMA), nothing to deploy"; \
	else \
		diff -u $(SCHEMA).production $(SCHEMA) || true; \
		rm -f $(SCHEMA).production; \
		echo; \
		echo "cktool cannot write to production. Deploy from the CloudKit Console:"; \
		echo "  1. CloudKit Database, then check the container in the top left — it opens"; \
		echo "     whichever container it feels like, so switch it to $(CONTAINER)"; \
		echo "  2. 'Deploy Schema Changes...' in the bottom left link list, under Settings"; \
		echo "     (not on the Schema pages), with the environment set to Development"; \
		echo "  3. review the additions listed above, then Deploy"; \
		$(OPEN) "https://icloud.developer.apple.com/dashboard/"; \
	fi
