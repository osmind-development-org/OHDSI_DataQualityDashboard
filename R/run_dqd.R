# ============================================================
# OMOP Data Quality Dashboard — PostgreSQL / CDM v5.4
# ============================================================
# Prerequisites:
#   install.packages(c("remotes", "DatabaseConnector", "SqlRender"))
#   remotes::install_github("OHDSI/DataQualityDashboard")
# ============================================================

library(DataQualityDashboard)
library(DatabaseConnector)

# ------------------------------------------------------------
# 1. CONNECTION — credentials loaded from .env
# ------------------------------------------------------------
# Reads DB_SERVER, DB_USER, DB_PASSWORD, DB_PORT from .env
# Never commit .env to version control (.gitignore handles this)
if (file.exists(".env")) {
  readRenviron(".env")
} else {
  stop("Missing .env file. Copy .env.example to .env and fill in your credentials.")
}

connectionDetails <- createConnectionDetails(
  dbms     = "postgresql",
  server   = paste0(Sys.getenv("DB_HOST"), "/", Sys.getenv("DB_NAME")),
  user     = Sys.getenv("DB_USER"),
  password = Sys.getenv("DB_PASSWORD"),
  port     = as.integer(Sys.getenv("DB_PORT", unset = "5432"))
)

# ------------------------------------------------------------
# 2. SCHEMA CONFIGURATION
# ------------------------------------------------------------
cdmDatabaseSchema     <- "analytics_omop"   # where your OMOP tables live
resultsDatabaseSchema <- "analytics_omop"   # where DQD writes its results table
                                             # (must exist; can be a separate schema)
cdmSourceName         <- "analytics_omop"   # label shown in the dashboard
cdmVersion            <- "5.4"

# ------------------------------------------------------------
# 3. OUTPUT
# ------------------------------------------------------------
outputFolder <- "./dqd_results"             # folder for JSON + logs
outputFile   <- "dqd_results.json"          # the file your HTML dashboard reads

# ------------------------------------------------------------
# 4. CHECK CONFIGURATION
# ------------------------------------------------------------
# Run all three levels (TABLE, FIELD, CONCEPT)
checkLevels <- c("TABLE", "FIELD", "CONCEPT")

# Run all three severity levels
checkSeverity <- c("fatal", "convention", "characterization")

# Skip vocabulary/reference tables — they are managed by OHDSI, not your ETL
tablesToExclude <- c(
  "CONCEPT", "VOCABULARY", "CONCEPT_ANCESTOR",
  "CONCEPT_RELATIONSHIP", "CONCEPT_CLASS",
  "CONCEPT_SYNONYM", "RELATIONSHIP", "DOMAIN"
)

# Exclude measureValueCompleteness due to duplicate denominator counts bug
# See: https://github.com/OHDSI/DataQualityDashboard/issues
allChecks <- DataQualityDashboard::listDqChecks(cdmVersion = cdmVersion)
checkNames <- unique(allChecks$checkDescriptions$checkName)
checkNames <- checkNames[!checkNames %in% c("measureValueCompleteness")]

# ------------------------------------------------------------
# 5. PERFORMANCE TUNING
# ------------------------------------------------------------
numThreads           <- 1     # increase if your DB supports parallel sessions
sqlOnly              <- FALSE # TRUE = generate SQL files without running them
sqlOnlyUnionCount    <- 1
sqlOnlyIncrementalInsert <- FALSE
verboseMode          <- TRUE

# Write results to a database table (dqdashboard_results) in resultsDatabaseSchema
writeToTable <- TRUE

# Also write a CSV alongside the JSON (handy for ad-hoc analysis)
writeToCsv   <- TRUE
csvFile      <- "dqd_results.csv"

# ------------------------------------------------------------
# 6. PREFLIGHT — verify CDM_SOURCE is populated
# ------------------------------------------------------------
# The DQD requires at least one row in CDM_SOURCE.
# If your table is empty, run this first (adjust values as needed):
#
# conn <- DatabaseConnector::connect(connectionDetails)
# sql <- "
#   INSERT INTO analytics_omop.cdm_source (
#     cdm_source_name, cdm_source_abbreviation, cdm_holder,
#     source_release_date, cdm_release_date, cdm_version, vocabulary_version
#   ) VALUES (
#     'analytics_omop', 'AOMOP', 'Your Organization',
#     CURRENT_DATE, CURRENT_DATE, 'v5.4', 'v5.0'
#   )
# "
# DatabaseConnector::executeSql(conn, sql)
# DatabaseConnector::disconnect(conn)

# ------------------------------------------------------------
# 7. RUN
# ------------------------------------------------------------
cat("Starting DQD execution...\n")
cat("  CDM schema   :", cdmDatabaseSchema, "\n")
cat("  Results schema:", resultsDatabaseSchema, "\n")
cat("  CDM version  :", cdmVersion, "\n")
cat("  Output folder:", outputFolder, "\n\n")

DataQualityDashboard::executeDqChecks(
  connectionDetails         = connectionDetails,
  cdmDatabaseSchema         = cdmDatabaseSchema,
  resultsDatabaseSchema     = resultsDatabaseSchema,
  cdmSourceName             = cdmSourceName,
  cdmVersion                = cdmVersion,
  numThreads                = numThreads,
  sqlOnly                   = sqlOnly,
  sqlOnlyUnionCount         = sqlOnlyUnionCount,
  sqlOnlyIncrementalInsert  = sqlOnlyIncrementalInsert,
  outputFolder              = outputFolder,
  outputFile                = outputFile,
  verboseMode               = verboseMode,
  writeToTable              = writeToTable,
  writeToCsv                = writeToCsv,
  csvFile                   = csvFile,
  checkLevels               = checkLevels,
  checkSeverity             = checkSeverity,
  tablesToExclude           = tablesToExclude,
  checkNames                = checkNames
)

cat("\n✅ DQD run complete.\n")
cat("JSON output:", file.path(outputFolder, outputFile), "\n")

# ------------------------------------------------------------
# 8. (OPTIONAL) LAUNCH THE BUILT-IN SHINY VIEWER
# ------------------------------------------------------------
# Uncomment to open OHDSI's own Shiny app in your browser:
#
# DataQualityDashboard::viewDqDashboard(
#   jsonPath = file.path(outputFolder, outputFile)
# )

# ------------------------------------------------------------
# 9. NEXT STEP: CUSTOM HTML DASHBOARD
# ------------------------------------------------------------
# Once the JSON is written, open dqd_dashboard.html in your browser.
# Point it at the JSON file path shown above.
# The dashboard reads the JSON and renders all charts and tables.
