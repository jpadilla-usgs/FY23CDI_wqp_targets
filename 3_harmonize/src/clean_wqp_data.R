#' @title Clean WQP data
#' 
#' @description 
#' Function to harmonize WQP data in preparation for further analysis. Included
#' in this function are steps to 1) unite diverse characteristic names by 
#' assigning them to more commonly-used water quality parameter names, 2) flag 
#' missing records, and 3) omit duplicated records.
#' 
#' @param wqp_data data frame containing the data downloaded from the WQP, 
#' where each row represents a data record. 
#' @param char_names_crosswalk data frame containing columns "char_name" and 
#' "parameter". The column "char_name" contains character strings representing 
#' known WQP characteristic names associated with each parameter.
#' @param commenttext_missing character string(s) indicating which strings from
#' the WQP column "ResultCommentText" correspond with missing result values. By 
#' default, the column "ResultCommentText" will be searched for the following 
#' strings: "analysis lost", "not analyzed", "not recorded", "not collected", 
#' and "no measurement taken", but other values may be added by passing in a new
#' vector with all values to be treated as missing.  
#' @param remove_duplicated_records logical; should records that are exactly-
#' duplicated across all columns be omitted from the dataset? Defaults to TRUE. 
#' 
#' @returns 
#' Returns a formatted and harmonized data frame containing data downloaded from 
#' the Water Quality Portal, where each row represents a unique data record.
#' 
clean_wqp_data <- function(wqp_data, 
                           char_names_crosswalk,
                           commenttext_missing = c('analysis lost', 'not analyzed', 
                                                   'not recorded', 'not collected', 
                                                   'no measurement taken'),
                           remove_duplicated_records = TRUE){

  # Clean data and assign flags if applicable
  wqp_data_clean <- wqp_data %>%
    # harmonize characteristic names by assigning a common parameter name
    # to the groups of characteristics supplied in `char_names_crosswalk`.
    left_join(y = char_names_crosswalk, by = c("CharacteristicName" = "char_name")) %>%
    # flag true missing results
    flag_missing_results(., commenttext_missing)
  
  # Check that records weren't unintentionally added when applying QC flags
  if(nrow(wqp_data_clean) > nrow(wqp_data)){
    stop(paste0("Records were unintentionally duplicated during the data flagging ", 
                "step. In the `char_names_crosswalk` table, check that each ",
                "'char_name' corresponds with one unique 'parameter' value."))
  }
  
  # Omit duplicate records and inform the user what we found
  if(remove_duplicated_records){
    wqp_data_clean <- distinct(wqp_data_clean)
    
    message(sprintf(paste0("Removed %s of %s records that were exactly ",
                           "duplicated across all columns"), 
                    (nrow(wqp_data) - nrow(wqp_data_clean)),
                    nrow(wqp_data)))
  }
  
  return(wqp_data_clean)
}


#' @title Flag missing results
#' 
#' @description 
#' Function to flag true missing results, i.e. when the result measure value 
#' and detection limit value are both NA, when "not reported" is found in the
#' column "ResultDetectionConditionText", or when any of the strings from
#' `commenttext_missing` are found in the column "ResultCommentText".
#' 
#' @param wqp_data data frame containing the data downloaded from the WQP, 
#' where each row represents a data record. Must contain the columns
#' "DetectionQuantitationLimitMeasure.MeasureValue", "ResultMeasureValue", 
#' "ResultDetectionConditionText", and "ResultCommentText".
#' @param commenttext_missing character string(s) indicating which strings from
#' the WQP column "ResultCommentText" correspond with missing result values.
#' 
#' @returns
#' Returns a data frame containing data downloaded from the Water Quality Portal,
#' where each row represents a data record. New columns appended to the original
#' data frame include flags for missing results. 
#' 
flag_missing_results <- function(wqp_data, commenttext_missing){
  
  wqp_data_out <- wqp_data %>%
    mutate(flag_missing_result = 
             ( is.na(ResultMeasureValue) & is.na(DetectionQuantitationLimitMeasure.MeasureValue) ) |
             grepl("not reported", ResultDetectionConditionText, ignore.case = TRUE) |
             grepl(paste(commenttext_missing, collapse = "|"), ResultCommentText, ignore.case = TRUE)
    )
  
  return(wqp_data_out)
}


#' @title Flag duplicated records
#' 
#' @description 
#' Function to flag duplicated rows based on a user-supplied definition
#' of a duplicate record. 
#' 
#' @details 
#' NOTE: THIS FUNCTION IS NOT CURRENTLY USED IN THE DATA DOWNLOAD PIPELINE.
#' This function is included as an optional helper function to flag records
#' that are considered duplicates based on a user-supplied `duplicate_definition`.
#' 
#' @param wqp_data data frame containing the data downloaded from the WQP, 
#' where each row represents a data record.
#' @param duplicate_definition character vector indicating which columns are
#' used to identify a duplicate record. Duplicate records are defined as those 
#' that share the same value for each column within `duplicate_definition`.
#'
#' @returns 
#' Returns a data frame containing data downloaded from the Water Quality Portal,
#' where each row represents a data record. New columns appended to the original
#' data frame include flags for duplicated records. 
#' 
flag_duplicates <- function(wqp_data, duplicate_definition){
  
  # Flag duplicate records using the `duplicate_definition`
  wqp_data_out <- wqp_data %>%
    group_by(across(all_of(duplicate_definition))) %>% 
    # arrange all rows to maintain consistency in row order across users/machines
    arrange(across(c(all_of(duplicate_definition), everything()))) %>%
    mutate(n_duplicated = n(),
           flag_duplicated_row = n_duplicated > 1) %>% 
    ungroup() %>%
    select(-n_duplicated)
  
  return(wqp_data_out)
}


#' @title Remove duplicated records
#' 
#' @description
#' Function to append additional flags to sets of duplicate rows that are then 
#' used to drop duplicates from the dataset. Currently, we randomly retain the 
#' first record in a set of duplicated rows and drop all others.
#' 
#' @details 
#' NOTE: THIS FUNCTION IS NOT CURRENTLY USED IN THE DATA DOWNLOAD PIPELINE.
#' This function is included as an optional helper function to omit records
#' that are considered duplicates based on a user-supplied `duplicate_definition`.
#' 
#' @param wqp_data data frame containing the data downloaded from the WQP, 
#' where each row represents a data record.
#' @param duplicate_definition character vector indicating which columns are
#' used to identify a duplicate record. Duplicate records are defined as those 
#' that share the same value for each column within `duplicate_definition`.
#' 
#' @returns 
#' Returns a data frame containing data downloaded from the Water Portal in which
#' duplicated rows have been removed. 
#' 
remove_duplicates <- function(wqp_data, duplicate_definition){

  wqp_data_out <- wqp_data %>%
    group_by(across(all_of(duplicate_definition))) %>% 
    # arrange all rows to maintain consistency in row order across users/machines;
    # the rows should be ordered the same way across machines so that when we 
    # "randomly" select the first duplicated row below, the output is consistent
    # for all users.
    arrange(across(c(all_of(duplicate_definition), everything()))) %>%
    # To help resolve duplicates, randomly select the first record
    # from each duplicated set and flag all others for exclusion.
    mutate(n_duplicated = n(),
           dup_number = seq(n_duplicated),
           flag_duplicate_drop_random = n_duplicated > 1 & dup_number != 1) %>%
    filter(flag_duplicate_drop_random == FALSE) %>%
    ungroup() %>%
    select(-c(n_duplicated, dup_number, flag_duplicate_drop_random))
  
  return(wqp_data_out)
}



