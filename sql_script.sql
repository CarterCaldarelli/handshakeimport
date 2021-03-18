with  
       --get today's date
       cur_date as (select trunc(sysdate) as today 
                      from dual)
     , param_year as (select 2021 as acyr from dual)
       --identify term based on today's date
     , cur_term as   (select    to_number(max(term_code)) as current_term
                         from    ban_term_codes
                        where    (select trunc(sysdate) from dual) > term_start_date
                          and    term_start_date < (select trunc(sysdate) from dual)) 
     --define term start dates
     , term_starts as (select    (select    term_start_date 
                                    from    ban_term_codes
                                   where    term_fa_proc_yr in (select acyr from param_year)
                                     and    substr(term_code,5,2) = 90) as fall_start
                               , (select    term_start_date 
                                    from    ban_term_codes
                                   where    term_fa_proc_yr in (select acyr from param_year)
                                     and    substr(term_code,5,2) = 10) as winter_start
                               , (select    term_start_date 
                                    from    ban_term_codes
                                   where    term_fa_proc_yr in (select acyr from param_year)
                                     and    substr(term_code,5,2) = 30) as spring_start
                               , (select    term_start_date 
                                    from    ban_term_codes
                                   where    term_fa_proc_yr in (select acyr from param_year)
                                     and    substr(term_code,5,2) = 60) as summer_start
                          from    ban_term_codes
                         where    rownum = 1)
     --dynamically generate termcode for next term
     , next_term as (select case when substr((select current_term from cur_term),5,6) in (90,10)
                                  then (select current_term from cur_term) + 20
                             else (select current_term from cur_term) + 30
                      end sub_term 
                      from dual)                   
     --identifies the upcoming term start date based on current term
     , next_import_term as (select case when substr((select current_term from cur_term),5,2) = 10 
                                   then (select spring_start from term_starts)
                                   when substr((select current_term from cur_term),5,2) = 30 
                                   then (select summer_start from term_starts)
                                   when substr((select current_term from cur_term),5,2) = 60 
                                   then (select fall_start from term_starts)
                                   when substr((select current_term from cur_term),5,2) = 90 
                                   then (select winter_start from term_starts)
                               end imp_term
                         from  dual)
     --sets the termcode for the main query depending on how many days today is away from identified term start date.  if date
     --is within 2 weeks prior to term start date, set termcode to next term, otherwise set termcode to current term.                                                    
     , set_term as (select case when (select today from cur_date) - (select imp_term from next_import_term) > -15
                                then (select sub_term from next_term)
                                else (select current_term from cur_term)
                            end dyn_term
                      from dual)
     --create lookup table for all enrolled undergraduate students with partnership type or hp3 cohort code, and total credits earned.  used to identify class.                  
     , ug_stu_lkup as (select distinct  enr_pidm as ug_pidm
                                      , enr_partnership_type as type 
                                      , case when enr_partnership_type = 'Pathways' then enr_campus_desc
                                             else enr_primary_campus_level
                                         end campus
                                      , enr_program_code as program
                                      , (nvl(lgpa_nlu_earned,0) + nvl(lgpa_transfer_earned,0)) as credits_earned
                               from     t_bi_enrollment
                                      , ban_gpa_level
                              where     enr_pidm = lgpa_pidm (+)
                                and    enr_term_code in (select dyn_term from set_term)
                                and    enr_level_code = 'UG'
                                and    (lgpa_level_code = 'UG' or lgpa_level_code is null))
     --gpa lookup tables by level
     , gr_gpa_lkup as (select    lgpa_pidm as gr_pidm 
                               , lgpa_nlu_gpa as gr_gpa
                         from    ban_gpa_level
                        where    lgpa_level_code = 'GR')
     , ug_gpa_lkup as (select    lgpa_pidm as ug_pidm
                               , lgpa_nlu_gpa as ug_gpa
                         from    ban_gpa_level
                        where    lgpa_level_code = 'UG')
     --advisor email address lookup table                      
     , adv_email_lkup as (select distinct   stu_pidm as adv_pidm
                                          , stu_email_employee as adv_email
                                     from   t_bi_student
                                          , ban_current_advisor
                                    where   stu_pidm = advr_advr_pidm
                                      and   stu_email_employee is not null)               
--select columns for import file                                    
select    stu_email_nlu as email_address
        , regexp_substr(stu_email_nlu, '^([A-Za-z0-9_\-\.]+)',1) as username
        , regexp_substr(stu_email_nlu, '^([A-Za-z0-9_\-\.]+)',1) as auth_identifier
        , stu_id as card_id
        , stu_first as first_name
        , stu_last as last_name
        , stu_mi as middle_name
        , stu_preferred_first_name as preferred_name
        --identifies ug class by cohort code if pathways or by credits if a/t or helix. uses degree code to identify master's or doctorate.
        , case when enr_degree_code in ('EDD','EDS','PHD','DPSY','DBA')
               then 'Doctorate'
               when enr_level_code = 'GR'
               then 'Masters'
               when enr_pidm in (select   ug_pidm
                                   from   ug_stu_lkup
                                  where   credits_earned is null
                                     or   credits_earned <45)
               then 'Freshman'
               when enr_pidm in (select   ug_pidm
                                   from   ug_stu_lkup
                                  where   credits_earned between 45 and 89.9)
               then 'Sophomore'
               when enr_pidm in (select   ug_pidm
                                   from   ug_stu_lkup
                                  where   credits_earned between 90 and 134.9)
               then 'Junior'
               when enr_pidm in (select   ug_pidm
                                   from   ug_stu_lkup
                                  where   credits_earned >= 135)
         then 'Senior'
               else ''
          end school_year_name
        , case when enr_degree_code in ('MAT','MED','MS','MA','MBA','MHA','MSED','MADE','MPA','MAED')
               then 'Masters'
               when enr_degree_code in ('BA','BS') 
               then 'Bachelors'
               when enr_degree_code in ('EDD','EDS','PHD','DPSY','DBA')
               then 'Doctorate'
               when enr_degree_code in ('AP','AS')
               then 'Associates'
               when enr_degree_code in ('CAS','CRTE','CRTB','CRTG')
               then 'Certificate'
               when enr_degree_code in ('None','0000UG','000000')
               then 'Non-Degree Seeking'
          end "primary_education:education_level_name"   
        --lookup gpa based on level code
        , case when enr_level_code = 'GR'
               then (select gr_gpa
                       from gr_gpa_lkup
                      where enr_pidm = gr_pidm)
               when enr_level_code = 'UG'
               then (select ug_gpa
                       from ug_gpa_lkup
                      where enr_pidm = ug_pidm)
          end "primary_education:cumulative_gpa"
        , enr_major_desc as "primary_education:major_names"
        , enr_major_desc as "primary_education:primary_major_name"
        , enr_minor_desc as "primary_education:minor_names"
        , enr_college_desc||' at national louis university' as "primary_education:college_name"
        , 'True' as "primary_education:currently_attending"
        , case when enr_partnership_type = 'Pathways'
               then enr_campus_desc
               else (select pcl.pcl_campus
                      from (select    distinct enr_pidm as pidm
                                    , case when enr_primary_campus_level = 'WH' then 'Wheeling'
                                           when enr_primary_campus_level = 'CH' then 'Chicago'
                                           when enr_primary_campus_level = 'NT' then 'On-line'
                                           when enr_primary_campus_level = 'LI' then 'Lisle'
                                           when enr_primary_campus_level = 'EL' then 'Elgin'
                                           when enr_primary_campus_level = 'TA' then 'Tampa'
                                           when enr_primary_campus_level = 'NS' then 'North Shore'
                                           when enr_primary_campus_level = 'KC' then 'Kendall Campus'
                                           when enr_primary_campus_level = 'BE' then 'Beloit'
                                           when enr_primary_campus_level = 'PD' then 'Professional Devl. Ctr.'
                                           else ''
                                      end  pcl_campus
                             from  t_bi_enrollment
                            where  enr_term_code in (select dyn_term from set_term)) pcl
                   where  enr_pidm = pcl.pidm)   
                end campus_name
        , stu_residency_ethnicity as ethnicity
        , case when stu_gender = 'F' 
               then 'Female'
               when stu_gender = 'M' 
               then 'Male'
               else ''
          end gender     
        , stu_phone_number as mobile_number
        --assign career advisor based on campus and program if pathways, assign olivia if helix, otherwise assign academic advisor
        , case when  enr_level_code = 'GR'
                and  enr_partnership_type not in ('Helix Online','NLU Online')
                and  enr_campus_code not in ('TA')
               then  null

               when  enr_program_code in ('BS MGT', 'BS HCL', 'BA ABS', 'BS MIS')
               then  'mjohnson192@nl.edu'

               when  enr_campus_code = 'NT'
                and  enr_program_code in (  'BA ECP'
                                          , 'BA ECE'
                                          , 'BA SS/ECE'
                                          , 'BA LAS/ECE'
                                          , 'BA ELED'
                                          , 'BA SS/ELED'
                                          , 'BA LAS/ELED'
                                          , 'BA SPE'
                                          , 'BA SS/SPE'
                                          , 'BA LAS/SPE'
                                          , 'BA_ECED'
                                          , '00 PBECE'
                                          , 'ND_ECED_CERT')
               then 'mjohnson192@nl.edu'

               when  enr_partnership_type in ('Helix online', 'NLU Online')
               then  'osmith6@nl.edu'

               when  enr_campus_code = 'WH'
                and  enr_level_code not in ('GR')
               then  'bsarkar@nl.edu'

               when  enr_campus_code not in ('WH','NT','TA')
                and  enr_program_code in ( 'BA ECP'
                                          ,'BA ECE'
                                          ,'BA SS/ECE'
                                          ,'BA LAS/ECE'
                                          ,'BA ELED'
                                          ,'BA SS/ELED'
                                          ,'BA LAS/ELED'
                                          ,'BA SPE'
                                          ,'BA SS/SPE'
                                          ,'BA LAS/SPE'
                                          ,'BA_ECED'
                                          ,'BA GSE'
                                          ,'00 PBECE'
                                          ,'ND_ECED_CERT')
               then  'dwilliams44@nl.edu'

               when   enr_campus_code not in ('WH','TA')
                and   enr_program_code in (  'BA BA'
                                           , 'BS CIS'
                                           , 'BA COMM'
                                           , 'BA AC'
                                           , 'BA_BUAD'
                                           , 'BA_BUAD_ONL'
                                           , 'BA_BUAD_PD')
               then   'mvicars1@nl.edu'

               when   enr_campus_code not in ('WH','TA')
                and   enr_program_code in ( 'BA CJ'
                                          , 'BA PSYCH'
                                          , 'BA HMS'
                                          , 'BA SOCSCI')
               then   'jmcgill3@nl.edu'

               when  enr_program_code in ( 'AAS_CULA'
                                          ,'BA_HOSM'
                                          ,'BA_CULA'
                                          ,'AAS_CULAACL'
                                          ,'AAS_BAPA'
                                          ,'CRTU PC'
                                          ,'CRTU BAPA'
                                          ,'BA_CULA_PD'
                                          ,'BA_HOSM_PD')
               then  'dbosco1@nl.edu'
               else  null
                end assigned_to_email_address
        --assign system level label used to control appointment flow in handshake
        , case when  enr_partnership_type = 'Pathways'
               then  'ft/dt'               
               when  enr_partnership_type in ('Helix Online', 'NLU Online')
               then  'helix'
               when  enr_level_code = 'UG'
                and  enr_partnership_type = 'Non-Partnership'
                and  enr_program_code not in ('AAS_CULA', 'BA_HOSM', 'BA_CULA', 'AAS_BAPA', 'CRTU PC', 'CRTU BAPA', 'BA_CULA_PD', 'BA_HOSM_PD')
               then  'a/t'
               when  enr_college_code = 'KC'
               then  'kendall'
               when  enr_level_code = 'GR'
                and  enr_partnership_type not in ('Helix Online', 'NLU Online')
               then  'grad_stu'
          end system_label_names
  from    t_bi_student
        , t_bi_enrollment
 where    stu_pidm = enr_pidm
   and    enr_term_status_code = 'REG'
   and    enr_term_code in (select dyn_term from set_term)
