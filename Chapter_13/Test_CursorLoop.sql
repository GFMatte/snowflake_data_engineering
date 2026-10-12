declare 
    return_message := '';
begin
    let log_cur cursor for
      select task_name, rows_processed 
      from PIPELINE_LOG 
      where run_group_id = 'd0056794-c162-45e7-9770-5fd249e5939d';

    for log_rec in log_cur do
      return_message := return_message ||
        'Task: '|| log_rec.task_name || 
        ' Rows processed: ' || log_rec.rows_processed ||  '\n';
    end for;
    return return_message;
end;