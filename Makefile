TEAM      := B6FVY827P9
CONTAINER := iCloud.net.kodare.Tada
SCHEMA    := cloudkit/development.ckdb

.PHONY: help cloudkit-export cloudkit-production-schema cloudkit-diff cloudkit-deploy-schema

help:
	@echo "CloudKit schema:"
	@echo "  make cloudkit-export            Export the development schema to $(SCHEMA)"
	@echo "  make cloudkit-production-schema  Print the current production schema"
	@echo "  make cloudkit-diff              Diff development against production"
	@echo "  make cloudkit-deploy-schema     Copy the development schema into production"
	@echo
	@echo "All of these need a CloudKit management token once per machine:"
	@echo "  create one at https://icloud.developer.apple.com/dashboard/ under"
	@echo "  Settings > Tokens > Management Tokens, then run:"
	@echo "  xcrun cktool save-token <token> --type management"

cloudkit-export:
	@mkdir -p $(dir $(SCHEMA))
	xcrun cktool export-schema --team-id $(TEAM) --container-id $(CONTAINER) \
		--environment development --output-file $(SCHEMA)

cloudkit-production-schema:
	@xcrun cktool export-schema --team-id $(TEAM) --container-id $(CONTAINER) \
		--environment production

cloudkit-diff: cloudkit-export
	@xcrun cktool export-schema --team-id $(TEAM) --container-id $(CONTAINER) \
		--environment production --output-file $(SCHEMA).production
	@if diff -u $(SCHEMA).production $(SCHEMA); then \
		echo "production is up to date"; \
	else \
		echo; \
		echo "cloudkit-deploy-schema would add the + lines above to production, permanently"; \
	fi; \
	rm -f $(SCHEMA).production

# The production schema is append-only: record types and fields created here can never be
# removed or retyped. Run cloudkit-diff first and read what is about to be added.
cloudkit-deploy-schema: cloudkit-export
	xcrun cktool import-schema --team-id $(TEAM) --container-id $(CONTAINER) \
		--environment production --file $(SCHEMA)
