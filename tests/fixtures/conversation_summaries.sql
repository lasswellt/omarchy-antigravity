-- Fixture schema + rows for tests/smoke. No real conversation content;
-- values are made up. Mirrors the schema documented in ../../findings.md.
CREATE TABLE `conversation_summaries` (
  `conversation_id` text,
  `title` text NOT NULL DEFAULT "",
  `preview` text NOT NULL DEFAULT "",
  `step_count` integer NOT NULL DEFAULT 0,
  `last_modified_time` datetime NOT NULL,
  `workspace_uris` text NOT NULL,
  `status` text NOT NULL DEFAULT "",
  `source` text NOT NULL DEFAULT "",
  `project_id` text NOT NULL DEFAULT "",
  `agent_name` text NOT NULL DEFAULT "",
  `parent_conversation_id` text NOT NULL DEFAULT "",
  `nesting_depth` integer NOT NULL DEFAULT 0,
  `battle_id` text NOT NULL DEFAULT "",
  `winning_conversation_id` text NOT NULL DEFAULT "",
  `not_fully_idle` numeric NOT NULL DEFAULT false,
  `killed` numeric NOT NULL DEFAULT false,
  `last_user_input_time` datetime NOT NULL,
  `last_user_input_step_index` integer NOT NULL DEFAULT -1,
  `app_data_dir` text NOT NULL DEFAULT "",
  `raw_summary` blob,
  `group_id` text NOT NULL DEFAULT "",
  PRIMARY KEY (`conversation_id`)
);

INSERT INTO conversation_summaries
  (conversation_id, title, step_count, last_modified_time, workspace_uris, status, agent_name, last_user_input_time)
VALUES
  ('fixture-today-1', 'Fix the build', 12, datetime('now', '-2 hours'), 'file:///home/example/project-a', 'CASCADE_RUN_STATUS_IDLE', 'cascade', datetime('now', '-2 hours')),
  ('fixture-today-2', 'Refactor the parser', 5, datetime('now', '-6 hours'), 'file:///home/example/project-a', 'CASCADE_RUN_STATUS_IDLE', 'cascade', datetime('now', '-6 hours')),
  ('fixture-last-week', 'Old conversation', 3, datetime('now', '-4 days'), 'file:///home/example/project-b', 'CASCADE_RUN_STATUS_IDLE', 'cascade', datetime('now', '-4 days')),
  ('fixture-old', 'Ancient conversation', 1, datetime('now', '-40 days'), 'file:///home/example/project-c', 'CASCADE_RUN_STATUS_IDLE', 'cascade', datetime('now', '-40 days'));
