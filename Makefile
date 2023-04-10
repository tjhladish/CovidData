
# processes assorted raw data to objects for use in various covid-abm
# analyses and figures
#
# briefly, this makefile manages creating a process/%.rds associated with each
# %.R file. add new files by creating a new *.R and linking the associated
# inputs ala line 29

# location to place digested files; can be locally defined to e.g. link to a
# network drive
RESDAT ?= process

# discover all possible targets
TARGETS := $(patsubst %.R,${RESDAT}/%.rds,$(wildcard *.R))

default: ${TARGETS}

${RESDAT}:
	mkdir $@

# macros for simplifying relationship definitions
R = $(strip Rscript $^ $(1) $@)

define linkdata =
${RESDAT}/$(1).rds: $(2)

endef

# linking raw (and processed data) to each output
$(eval $(call linkdata,ACS_2019_pop,ACS_2019_pop_data.csv))
$(eval $(call linkdata,cdc_vax,cdc_covid-19_vax_data.csv ${RESDAT}/ACS_2019_pop.rds))

# the actual target definition
${RESDAT}/%.rds: %.R | ${RESDAT}
	$(call R)
