TEAM      := B6FVY827P9
CONTAINER := iCloud.net.kodare.Tada
SCHEMA    := cloudkit/development.ckdb

.PHONY: help cloudkit-export cloudkit-production-schema cloudkit-diff cloudkit-deploy-schema

help:
	@echo "CloudKit schema:"
	@echo "  make cloudkit-export            Export the development schema to $(SCHEMA)"
	@echo "  make cloudkit-production-schema  Print the current production schema"
	@echo "  make cloudkit-diff              Diff development against production"
	@echo "  make cloudkit-deploy-schema     Show the diff, then deploy from the Console"
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

# cktool can only read production: import-schema and validate-schema both reject it with
# "endpoint not applicable in the environment 'production'". Deploying the development schema
# to production is only possible from the CloudKit Console, so this target shows the diff and
# hands over. The production schema is append-only — whatever is deployed can never be removed
# or retyped, so read the additions above before clicking Deploy.
cloudkit-deploy-schema: cloudkit-diff
	@echo
	@echo "cktool cannot write to production. Deploy from the CloudKit Console:"
	@echo "  1. select the $(CONTAINER) container"
	@echo "  2. open any Schema page, then 'Deploy Schema Changes...'"
	@echo "  3. review the additions listed above, then Deploy"
	@open "https://icloud.developer.apple.com/dashboard/"
