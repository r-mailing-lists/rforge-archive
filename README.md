# rforge-archive

Mailing list archives from [R-Forge](https://r-forge.r-project.org/), pooled into one repository ahead of the service's [retirement](https://www.zeileis.org/news/rforge_codeberg/).

It holds every R-Forge discussion list that had a public archive with at least one message when the snapshot was taken in October 2026: 82 lists, 13,326 messages, spanning February 2008 to November 2025. See [`lists.tsv`](lists.tsv) for the full index with message counts and date ranges.

The set of lists was built from three sources, because no single one is complete: Mailman's public list overview (1,300 lists), the mailing list page of every R-Forge project (2,061 projects), and every list name the Internet Archive's Wayback Machine has recorded on the list server. Five lists here, including `datatable-help` and `genabel-devel`, are absent from the Mailman overview and were found through the other two.

## Structure

Each list has its own directory, laid out like the per-list archive repositories in [r-mailing-lists](https://github.com/r-mailing-lists):

- `<list>/raw/` - .mbox files downloaded from `https://lists.r-forge.r-project.org/pipermail/<list>/`, one per archive period
- `<list>/processed/` - Structured JSON output from [rmail-parser](https://github.com/r-mailing-lists/rmail-parser), one file per month
- `<list>/meta.json` - List statistics
- `<list>/config.json` - List name, description, and source URL

`lists.tsv` at the top level indexes all lists.

## Reading the data

Each list is published as its own Parquet file in [r-mailing-lists/data](https://github.com/r-mailing-lists/data), alongside the other R mailing lists:

``` r
source("https://raw.githubusercontent.com/r-mailing-lists/data/main/scripts/rml.R")

adegenet <- rml_read("adegenet-forum")
```

To work from this repository directly, read `lists.tsv` to find a list and then the monthly JSON files under its `processed/` directory.

## What is not here

- **rcpp-devel** has its own repository, [r-mailing-lists/rcpp-devel](https://github.com/r-mailing-lists/rcpp-devel).
- **Commit lists.** R-Forge's more than 1,100 `<project>-commits` lists carry automated SVN commit notifications, not discussion.
- **Empty lists.** 89 discussion lists never received a message.
- **Member-only archives.** `lme4-authors`, `opm-support`, `rqda-help`, `sedar-devel`, and `topklists-development` restrict their archives to subscribers.
- **Lists removed earlier.** About 20 discussion lists, among them `vegan-devel`, `statet-user`, `mlr-general`, and `flr-help`, were deleted from R-Forge before the snapshot. The Wayback Machine holds scattered pages from a few of them.

`diagnosismed-list` is archived here for completeness but is mostly spam (342 of its 410 messages), so it is not published to r-mailing-lists/data.

## Updating

The lists are dormant or nearly so, so there is no scheduled update. To pull anything new before R-Forge shuts down, run the **Update Archive** workflow, or locally:

``` bash
RMAIL_PARSER=/path/to/rmail-parser scripts/update.sh
```

A download that fails or comes back empty never replaces a file that is already archived, so the script is safe to run after R-Forge is gone.
