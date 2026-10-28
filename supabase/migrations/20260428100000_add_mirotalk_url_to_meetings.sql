-- Add mirotalk_url column to meetings table for storing meeting room URLs
ALTER TABLE meetings 
ADD COLUMN IF NOT EXISTS mirotalk_url TEXT;

-- Enable RLS
ALTER TABLE meetings ENABLE ROW LEVEL SECURITY;

-- Create policy for users to read meetings they're participants of
DROP POLICY IF EXISTS "Users can read meetings they're in" ON meetings;
CREATE POLICY "Users can read meetings they're in" ON meetings FOR SELECT
  USING (
    host_id IN (SELECT id FROM users WHERE auth.uid() = id)
    OR chat_id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );