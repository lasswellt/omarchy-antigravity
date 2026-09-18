-- Fixture schema + rows for tests/smoke. No real conversation content; values
-- are made up. Schema is copied verbatim from a live database (both the CLI's
-- and the IDE's are identical — see roadmap.md §0).
--
-- Timestamps deliberately reproduce the exact stored format, including
-- nanosecond precision and the +00:00 offset:
--     2026-09-18 20:02:07.202040507+00:00
-- Writing these as bare datetime('now') would test a format Antigravity never
-- actually produces.
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
  ('fixture-today-1', 'Fix the build', 12,
   strftime('%Y-%m-%d %H:%M:%S', 'now', '-2 hours') || '.202040507+00:00',
   'file:///home/example/project-a', 'CASCADE_RUN_STATUS_IDLE', 'cascade',
   strftime('%Y-%m-%d %H:%M:%S', 'now', '-2 hours') || '.202040507+00:00'),
  ('fixture-today-2', 'Refactor the parser', 5,
   strftime('%Y-%m-%d %H:%M:%S', 'now', '-3 hours') || '.118273645+00:00',
   'file:///home/example/project-a', 'CASCADE_RUN_STATUS_IDLE', 'cascade',
   strftime('%Y-%m-%d %H:%M:%S', 'now', '-3 hours') || '.118273645+00:00'),
  ('fixture-last-week', 'Old conversation', 3,
   strftime('%Y-%m-%d %H:%M:%S', 'now', '-4 days') || '.900112233+00:00',
   'file:///home/example/project-b', 'CASCADE_RUN_STATUS_IDLE', 'cascade',
   strftime('%Y-%m-%d %H:%M:%S', 'now', '-4 days') || '.900112233+00:00'),
  ('fixture-old', 'Ancient conversation', 1,
   strftime('%Y-%m-%d %H:%M:%S', 'now', '-40 days') || '.554433221+00:00',
   'file:///home/example/project-c', 'CASCADE_RUN_STATUS_IDLE', 'cascade',
   strftime('%Y-%m-%d %H:%M:%S', 'now', '-40 days') || '.554433221+00:00');
