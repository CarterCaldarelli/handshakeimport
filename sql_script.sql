with  
       --get today's date
       cur_date as (select trunc(sysdate) as today 
                      from dual)
       --set academic year
     , param_year as (select 2021 as acyr from dual)
       --identify term based on today's date
     , cur_term as   (select    to_number(max(term_code)) as current_term
                         from    ban_termcodes
                        where    (select trunc(sysdate) from dual) > term_start_date
                          and    term_start_date < (select trunc(sysdate) from dual)) 
       --dynamically generate term start dates based on academic year
     , term_starts as (select    (select    term_start_date 
                                    from    ban_termcodes
                                   where    term_fa_proc_yr in (select acyr from param_year)
                                     and    substr(term_code,5,2) = 90) as fall_start
                               , (select    term_start_date 
                                    from    ban_termcodes
                                   where    term_fa_proc_yr in (select acyr from param_year)
                                     and    substr(term_code,5,2) = 10) as winter_start
                               , (select    term_start_date 
                                    from    ban_termcodes
                                   where    term_fa_proc_yr in (select acyr from param_year)
                                     and    substr(term_code,5,2) = 30) as spring_start
                               , (select    term_start_date 
                                    from    ban_termcodes
                                   where    term_fa_proc_yr in (select acyr from param_year)
                                     and    substr(term_code,5,2) = 60) as summer_start
                          from    ban_termcodes
                         where    rownum = 1)
     --dynamically generate termcode for next term
     , nxt_term as (select    termxwalk_term as next_term
                       from    termxwalk
                            , (select    termxwalk_num + 1 as nxt_term_walk
                                 from    termxwalk
                                where    termxwalk_term = (select current_term from cur_term)) nxt 
                      where  nxt.nxt_term_walk = termxwalk_num)                   
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
                                then (select next_term from nxt_term)
                                else (select current_term from cur_term)
                            end dyn_term
                      from dual)
     --create lookup table for all enrolled undergraduate students with partnership type or hp3 cohort code, and total credits earned.  Used to identify class.                  
     , ug_lkup as (select distinct  pidm as ug_pidm
                                      , partnership_type as type 
                                      , case when partnership_type = 'Pathways' then campus_desc
                                             else primary_campus_level
                                         end campus
                                      , program_code as program
                                      , (nvl(lgpa_nlu_earned,0) + nvl(lgpa_transfer_earned,0)) as credits_earned
                               from     enrollment_table
                                      , ban_gpalevel
                              where     pidm = lgpa_pidm (+)
                                and    term_code in (select dyn_term from set_term)
                                and    level_code = 'UG'
                                and    (lgpa_level_code = 'UG' or lgpa_level_code is null))
     --gpa lookup tables by level
     , gr_gpa_lkup as (select    lgpa_pidm as gr_pidm 
                               , lgpa_nlu_gpa as gr_gpa
                         from    ban_gpalevel
                        where    lgpa_level_code = 'GR')
     , ug_gpa_lkup as (select    lgpa_pidm as ug_pidm
                               , lgpa_nlu_gpa as ug_gpa
                         from    ban_gpalevel
                        where    lgpa_level_code = 'UG')
     --advisor email address lookup table                      
     , adv_email_lkup as (select distinct   pidm as adv_pidm
                                          , email_employee as adv_email
                                     from   student_table
                                          , ban_current_advisor
                                    where   pidm = advr_advr_pidm
                                      and   email_employee is not null)               
--select columns for import file                                    
select    email_nlu as email_address
        , regexp_substr(email_nlu, '^([A-Za-z0-9_\-\.]+)',1) as username
        , regexp_substr(email_nlu, '^([A-Za-z0-9_\-\.]+)',1) as auth_identifier
        , id as card_id
        , first as first_name
        , last as last_name
        , mi as middle_name
        , preferred_first_name as preferred_name
        --identifies UG class by credits. Uses degree code to identify master's or doctorate.
        , case when degree_code in ('EDD','EDS','PHD','DPSY','DBA')
               then 'Doctorate'
               when level_code = 'GR'
               then 'Masters'
               when enrollment_table.pidm in (select   ug_pidm
                                   from   ug_lkup
                                  where   credits_earned is null
                                     or   credits_earned <45)
               then 'Freshman'
               when enrollment_table.pidm in (select   ug_pidm
                                   from   ug_lkup
                                  where   credits_earned between 45 and 89.9)
               then 'Sophomore'
               when enrollment_table.pidm in (select   ug_pidm
                                   from   ug_lkup
                                  where   credits_earned between 90 and 134.9)
               then 'Junior'
               when enrollment_table.pidm in (select   ug_pidm
                                   from   ug_lkup
                                  where   credits_earned >= 135)
         then 'Senior'
               else ''
          end school_year_name
        , case when degree_code in ('MAT','MED','MS','MA','MBA','MHA','MSED','MADE','MPA','MAED')
               then 'Masters'
               when degree_code in ('BA','BS') 
               then 'Bachelors'
               when degree_code in ('EDD','EDS','PHD','DPSY','DBA')
               then 'Doctorate'
               when degree_code in ('AP','AS')
               then 'Associates'
               when degree_code in ('CAS','CRTE','CRTB','CRTG')
               then 'Certificate'
               when degree_code in ('None','0000UG','000000')
               then 'Non-Degree Seeking'
          end "primary_education:education_level_name"   
        --lookup gpa based on level code
        , case when level_code = 'GR'
               then (select gr_gpa
                       from gr_gpa_lkup
                      where enrollment_table.pidm = gr_pidm)
               when level_code = 'UG'
               then (select ug_gpa
                       from ug_gpa_lkup
                      where enrollment_table.pidm = ug_pidm)
          end "primary_education:cumulative_gpa"
        , major_desc as "primary_education:major_names"
        , major_desc as "primary_education:primary_major_name"
        , minor_desc as "primary_education:minor_names"
        , college_desc||' at national louis university' as "primary_education:college_name"
        , 'True' as "primary_education:currently_attending"
        , case when partnership_type = 'Pathways'
               then campus_desc
               else (select pcl.pcl_campus
                      from (select    distinct pidm as pidm
                                    , case when primary_campus_level = 'WH' then 'Wheeling'
                                           when primary_campus_level = 'CH' then 'Chicago'
                                           when primary_campus_level = 'NT' then 'On-line'
                                           when primary_campus_level = 'LI' then 'Lisle'
                                           when primary_campus_level = 'EL' then 'Elgin'
                                           when primary_campus_level = 'TA' then 'Tampa'
                                           when primary_campus_level = 'NS' then 'North Shore'
                                           when primary_campus_level = 'KC' then 'Kendall Campus'
                                           when primary_campus_level = 'BE' then 'Beloit'
                                           when primary_campus_level = 'PD' then 'Professional Devl. Ctr.'
                                           else ''
                                      end  pcl_campus
                             from  enrollment_table
                            where  term_code in (select dyn_term from set_term)) pcl
                   where  pidm = pcl.pidm)   
                end campus_name
        , residency_ethnicity as ethnicity
        , case when gender = 'F' 
               then 'Female'
               when gender = 'M' 
               then 'Male'
               else ''
          end gender     
        , phone_number as mobile_number
        --assign career advisor based on campus and program
        , case when  level_code = 'GR'
                and  partnership_type not in ('Helix Online','NLU Online')
                and  campus_code not in ('TA')
               then  null

               when  program_code in ('BS MGT', 'BS HCL', 'BA ABS', 'BS MIS')
               then  'Career Advisor 1'

               when  campus_code = 'NT'
                and  program_code in (  'BA ECP'
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
               then 'Career Advisor 1'

               when  partnership_type in ('Helix online', 'NLU Online')
               then  'Career Advisor 2'

               when  campus_code = 'WH'
                and  level_code not in ('GR')
               then  'Career Advisor 3'

               when  campus_code not in ('WH','NT','TA')
                and  program_code in ( 'BA ECP'
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
               then  'Career Advisor 4'

               when   campus_code not in ('WH','TA')
                and   program_code in (  'BA BA'
                                           , 'BS CIS'
                                           , 'BA COMM'
                                           , 'BA AC'
                                           , 'BA_BUAD'
                                           , 'BA_BUAD_ONL'
                                           , 'BA_BUAD_PD')
               then   'Career Advisor 5'

               when   campus_code not in ('WH','TA')
                and   program_code in ( 'BA CJ'
                                          , 'BA PSYCH'
                                          , 'BA HMS'
                                          , 'BA SOCSCI')
               then   'Career Advisor 6'

               when   program_code in ( 'AAS_CULA'
                                          ,'BA_HOSM'
                                          ,'BA_CULA'
                                          ,'AAS_CULAACL'
                                          ,'AAS_BAPA'
                                          ,'CRTU PC'
                                          ,'CRTU BAPA'
                                          ,'BA_CULA_PD'
                                          ,'BA_HOSM_PD')
               then  'Career Advisor 7'
               else  null
                end assigned_to_email_address
        --assign system level label used to control appointment flow in handshake
        , case when  partnership_type = 'Pathways'
               then  'ft/dt'               
               when  partnership_type in ('Helix Online', 'NLU Online')
               then  'helix'
               when  level_code = 'UG'
                and  partnership_type = 'Non-Partnership'
                and  program_code not in ('AAS_CULA', 'BA_HOSM', 'BA_CULA', 'AAS_BAPA', 'CRTU PC', 'CRTU BAPA', 'BA_CULA_PD', 'BA_HOSM_PD')
               then  'a/t'
               when  college_code = 'KC'
               then  'kendall'
               when  level_code = 'GR'
                and  partnership_type not in ('Helix Online', 'NLU Online')
               then  'grad_stu'
          end system_label_names
  from    student_table
        , enrollment_table
 where    student_table.pidm = enrollment_table.pidm
   and    term_status_code = 'REG'
   and    term_code in (select dyn_term from set_term)
