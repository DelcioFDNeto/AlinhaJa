-- Split 'Matriz / CD' into 'Matriz' and 'CD / Fábrica'

-- 1. Ensure 'Matriz' exists in branches
INSERT INTO public.branches (name) 
VALUES ('Matriz') 
ON CONFLICT (name) DO NOTHING;

-- 2. Ensure 'CD / Fábrica' exists in branches
INSERT INTO public.branches (name) 
VALUES ('CD / Fábrica') 
ON CONFLICT (name) DO NOTHING;

-- 3. Migrate any existing users from the old 'Matriz / CD' to 'Matriz'
DO $$
DECLARE
  v_old_id UUID;
  v_new_id UUID;
BEGIN
  -- Get ID of 'Matriz / CD'
  SELECT id INTO v_old_id FROM public.branches WHERE name = 'Matriz / CD';
  -- Get ID of 'Matriz'
  SELECT id INTO v_new_id FROM public.branches WHERE name = 'Matriz';

  IF v_old_id IS NOT NULL AND v_new_id IS NOT NULL THEN
    -- Update users
    UPDATE public.users 
    SET branch_id = v_new_id 
    WHERE branch_id = v_old_id;
    
    -- Delete old ununified branch
    DELETE FROM public.branches WHERE id = v_old_id;
  END IF;
END $$;
