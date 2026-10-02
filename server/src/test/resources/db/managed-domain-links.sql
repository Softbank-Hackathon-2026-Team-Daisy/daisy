-- TEST ONLY: management owner integrates this cycle after deployment_target exists.
ALTER TABLE target ADD CONSTRAINT target_current_deployment_fk
  FOREIGN KEY(current_deployment_target_id,id,project_id) REFERENCES deployment_target(id,target_id,project_id);
