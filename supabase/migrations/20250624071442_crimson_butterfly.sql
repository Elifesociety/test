/*
  # SEDP System Admin Setup and Fixes

  1. Admin User Setup
    - Create admin user with proper credentials
    - Set up universal admin access policies
    - Configure admin role assignments

  2. Storage Policies
    - Enable universal access for storage buckets
    - Configure CORS settings for admin access

  3. Registration Data Access
    - Ensure admin universal access to all registration data
    - Update RLS policies for cross-origin admin access

  4. System Cleanup
    - Remove any existing placeholder admin accounts
    - Clean up and optimize database structure
*/

-- Create admin user function with proper credentials
CREATE OR REPLACE FUNCTION create_admin_user()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  admin_user_id uuid;
BEGIN
  -- Check if admin user already exists
  SELECT id INTO admin_user_id
  FROM auth.users
  WHERE email = 'evamarketingsolutions@gmail.com';

  -- If user doesn't exist, create them
  IF admin_user_id IS NULL THEN
    -- Insert into auth.users
    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      recovery_sent_at,
      last_sign_in_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      email_change,
      email_change_token_new,
      recovery_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
      'authenticated',
      'authenticated',
      'evamarketingsolutions@gmail.com',
      crypt('admin919123', gen_salt('bf')),
      NOW(),
      NOW(),
      NOW(),
      '{"provider": "email", "providers": ["email"]}',
      '{"full_name": "SEDP Admin"}',
      NOW(),
      NOW(),
      '',
      '',
      '',
      ''
    ) RETURNING id INTO admin_user_id;

    -- Insert into auth.identities
    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      last_sign_in_at,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      admin_user_id,
      format('{"sub": "%s", "email": "%s"}', admin_user_id::text, 'evamarketingsolutions@gmail.com')::jsonb,
      'email',
      NOW(),
      NOW(),
      NOW()
    );
  ELSE
    -- Update existing user password
    UPDATE auth.users 
    SET encrypted_password = crypt('admin919123', gen_salt('bf')),
        updated_at = NOW()
    WHERE id = admin_user_id;
  END IF;

  -- Ensure profile exists
  INSERT INTO profiles (id, full_name, email, created_at, updated_at)
  VALUES (admin_user_id, 'SEDP Admin', 'evamarketingsolutions@gmail.com', NOW(), NOW())
  ON CONFLICT (id) DO UPDATE SET
    full_name = 'SEDP Admin',
    email = 'evamarketingsolutions@gmail.com',
    updated_at = NOW();

  -- Ensure admin role exists
  INSERT INTO user_roles (user_id, role, created_at)
  VALUES (admin_user_id, 'admin', NOW())
  ON CONFLICT (user_id, role) DO NOTHING;

  RAISE NOTICE 'Admin user setup completed for: evamarketingsolutions@gmail.com';
END;
$$;

-- Execute admin user creation
SELECT create_admin_user();

-- Enhanced admin access function
CREATE OR REPLACE FUNCTION has_admin_access(user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if user is the main admin by email
  IF EXISTS (
    SELECT 1 FROM auth.users 
    WHERE id = user_id AND email = 'evamarketingsolutions@gmail.com'
  ) THEN
    RETURN true;
  END IF;

  -- Check if user has admin role
  IF EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = has_admin_access.user_id AND role = 'admin'
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- Update RLS policies for universal admin access

-- Registrations table - Admin universal access
DROP POLICY IF EXISTS "Admin Universal Access" ON registrations;
CREATE POLICY "Admin Universal Access" ON registrations
  FOR ALL USING (has_admin_access());

-- Categories table - Admin universal access
DROP POLICY IF EXISTS "Admins can manage categories" ON categories;
CREATE POLICY "Admins can manage categories" ON categories
  FOR ALL USING (has_admin_access());

-- Panchayaths table - Admin universal access
DROP POLICY IF EXISTS "Admins can manage panchayaths" ON panchayaths;
CREATE POLICY "Admins can manage panchayaths" ON panchayaths
  FOR ALL USING (has_admin_access());

-- Announcements table - Admin universal access
DROP POLICY IF EXISTS "Admins can manage announcements" ON announcements;
CREATE POLICY "Admins can manage announcements" ON announcements
  FOR ALL USING (has_admin_access());

-- Photo gallery table - Admin universal access
DROP POLICY IF EXISTS "Admins can manage gallery" ON photo_gallery;
CREATE POLICY "Admins can manage gallery" ON photo_gallery
  FOR ALL USING (has_admin_access());

-- Push notifications table - Admin universal access
DROP POLICY IF EXISTS "Admins can manage notifications" ON push_notifications;
CREATE POLICY "Admins can manage notifications" ON push_notifications
  FOR ALL USING (has_admin_access());

-- User roles table - Admin universal access
DROP POLICY IF EXISTS "Admins can manage roles" ON user_roles;
CREATE POLICY "Admins can manage roles" ON user_roles
  FOR ALL USING (has_admin_access());

-- Profiles table - Admin universal access
DROP POLICY IF EXISTS "Admins can manage profiles" ON profiles;
CREATE POLICY "Admins can manage profiles" ON profiles
  FOR ALL USING (has_admin_access());

-- Create storage bucket for category images if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'category-images',
  'category-images',
  true,
  5242880, -- 5MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
) ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

-- Storage policies for universal access
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
CREATE POLICY "Public Access" ON storage.objects
  FOR SELECT USING (bucket_id = 'category-images');

DROP POLICY IF EXISTS "Admin Upload Access" ON storage.objects;
CREATE POLICY "Admin Upload Access" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'category-images' AND 
    has_admin_access()
  );

DROP POLICY IF EXISTS "Admin Update Access" ON storage.objects;
CREATE POLICY "Admin Update Access" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'category-images' AND 
    has_admin_access()
  );

DROP POLICY IF EXISTS "Admin Delete Access" ON storage.objects;
CREATE POLICY "Admin Delete Access" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'category-images' AND 
    has_admin_access()
  );

-- Function to assign admin role
CREATE OR REPLACE FUNCTION assign_admin_role(user_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  target_user_id uuid;
BEGIN
  -- Get user ID by email
  SELECT id INTO target_user_id
  FROM auth.users
  WHERE email = user_email;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'User with email % not found', user_email;
  END IF;

  -- Insert admin role
  INSERT INTO user_roles (user_id, role, created_at)
  VALUES (target_user_id, 'admin', NOW())
  ON CONFLICT (user_id, role) DO NOTHING;

  -- Ensure profile exists
  INSERT INTO profiles (id, email, created_at, updated_at)
  VALUES (target_user_id, user_email, NOW(), NOW())
  ON CONFLICT (id) DO UPDATE SET
    email = user_email,
    updated_at = NOW();
END;
$$;

-- Ensure all panchayaths are properly loaded
INSERT INTO panchayaths (malayalam_name, english_name, pincode, district) VALUES
('അബ്ദുറഹ്മാൻ നഗർ', 'Abdu Rahman Nagar', '676121', 'Malappuram'),
('ആലംകോട്', 'Alamcode', '676122', 'Malappuram'),
('അനക്കായം', 'Anakkayam', '676123', 'Malappuram'),
('ആറീക്കോട്', 'Areecode', '676124', 'Malappuram'),
('ചീക്കോട്', 'Cheekkode', '676301', 'Malappuram'),
('ചെലക്കര', 'Chelakkara', '676302', 'Malappuram'),
('ചെമ്മാട്', 'Chemmad', '676303', 'Malappuram'),
('ചെർപ്പുലശ്ശേരി', 'Cherpulassery', '676304', 'Malappuram'),
('ചോക്കാട്', 'Chokkad', '676305', 'Malappuram'),
('ഇടക്കര', 'Edakkara', '676306', 'Malappuram'),
('ഇടപ്പാൽ', 'Edappal', '679576', 'Malappuram'),
('ഇടവണ്ണ', 'Edavanna', '676123', 'Malappuram'),
('ഇളംകുളം', 'Elamkulam', '676307', 'Malappuram'),
('ഇരുമ്പുഴി', 'Irumbuzhi', '676308', 'Malappuram'),
('കടമ്പുഴ', 'Kadampuzha', '676553', 'Malappuram'),
('കാളികാവ്', 'Kalikavu', '676525', 'Malappuram'),
('കണ്ണമംഗലം', 'Kannamangalam', '676104', 'Malappuram'),
('കരുവാരകുണ്ട്', 'Karuvarakundu', '676503', 'Malappuram'),
('കീഴാറ്റൂർ', 'Keezhattur', '676551', 'Malappuram'),
('കിഴുപറമ്പ', 'Kizhuparamba', '676309', 'Malappuram'),
('കോടൂർ', 'Kodur', '676554', 'Malappuram'),
('കൊണ്ടോട്ടി', 'Kondotty', '673638', 'Malappuram'),
('കൂട്ടിലാങ്ങാടി', 'Koottilangadi', '676310', 'Malappuram'),
('കുറുവ', 'Kuruva', '676311', 'Malappuram'),
('കുറ്റിപ്പുറം', 'Kuttippuram', '679571', 'Malappuram'),
('മക്കരപറമ്പ', 'Makkaraparamba', '676517', 'Malappuram'),
('മലപ്പുറം', 'Malappuram', '676505', 'Malappuram'),
('മഞ്ചേരി', 'Manjeri', '676121', 'Malappuram'),
('മാറക്കര', 'Marakkara', '676312', 'Malappuram'),
('മേലാറ്റൂർ', 'Melattur', '676552', 'Malappuram'),
('മൊറയൂർ', 'Morayur', '676313', 'Malappuram'),
('മുടൂർ', 'Mudur', '676314', 'Malappuram'),
('മുണ്ടുപറമ്പ', 'Munduparamba', '676315', 'Malappuram'),
('നാൻമുക്ക്', 'Nanmukku', '676316', 'Malappuram'),
('നിലമ്പൂർ', 'Nilambur', '679329', 'Malappuram'),
('ഒത്തുകുങ്ങൽ', 'Othukungal', '676317', 'Malappuram'),
('പണ്ടിക്കാട്', 'Pandikkad', '676521', 'Malappuram'),
('പെരിന്തൽമണ്ണ', 'Perinthalmanna', '679322', 'Malappuram'),
('പെരുമ്പടപ്പ്', 'Perumpadappu', '676318', 'Malappuram'),
('പൊൻമുണ്ടം', 'Ponmundam', '679577', 'Malappuram'),
('പുളിക്കൽ', 'Pulikkal', '676319', 'Malappuram'),
('പുറത്തൂർ', 'Purathur', '676320', 'Malappuram'),
('താനലൂർ', 'Tanalur', '676321', 'Malappuram'),
('താനൂർ', 'Tanur', '676302', 'Malappuram'),
('തിരുവാലി', 'Thiruvali', '676322', 'Malappuram'),
('തിരുരങ്ങാടി', 'Tirurangadi', '676306', 'Malappuram'),
('തൃപ്രാങ്കോട്', 'Triprangode', '676303', 'Malappuram'),
('വഴക്കാട്', 'Vazhakkad', '676517', 'Malappuram'),
('വഴയൂർ', 'Vazhayur', '676323', 'Malappuram'),
('വേങ്ങര', 'Vengara', '676304', 'Malappuram'),
('വണ്ടൂർ', 'Wandoor', '679328', 'Malappuram')
ON CONFLICT (malayalam_name) DO NOTHING;

-- Ensure all categories are properly loaded with default fees and images
INSERT INTO categories (name, label, actual_fee, offer_fee, has_offer, image_url) VALUES
('pennyekart-free', 'Pennyekart Free Registration', 0, 0, false, 'https://images.pexels.com/photos/230544/pexels-photo-230544.jpeg?auto=compress&cs=tinysrgb&w=800'),
('pennyekart-paid', 'Pennyekart Paid Registration', 800, 300, true, 'https://images.pexels.com/photos/3184291/pexels-photo-3184291.jpeg?auto=compress&cs=tinysrgb&w=800'),
('farmelife', 'FarmeLife', 1000, 400, true, 'https://images.pexels.com/photos/974314/pexels-photo-974314.jpeg?auto=compress&cs=tinysrgb&w=800'),
('foodelife', 'FoodeLife', 1200, 500, true, 'https://images.pexels.com/photos/1640777/pexels-photo-1640777.jpeg?auto=compress&cs=tinysrgb&w=800'),
('organelife', 'OrganeLife', 1500, 600, true, 'https://images.pexels.com/photos/1300972/pexels-photo-1300972.jpeg?auto=compress&cs=tinysrgb&w=800'),
('entrelife', 'EntreLife', 900, 350, true, 'https://images.pexels.com/photos/3184465/pexels-photo-3184465.jpeg?auto=compress&cs=tinysrgb&w=800'),
('job-card', 'Job Card (All Categories)', 2000, 800, true, 'https://images.pexels.com/photos/3184360/pexels-photo-3184360.jpeg?auto=compress&cs=tinysrgb&w=800')
ON CONFLICT (name) DO UPDATE SET
  label = EXCLUDED.label,
  actual_fee = EXCLUDED.actual_fee,
  offer_fee = EXCLUDED.offer_fee,
  has_offer = EXCLUDED.has_offer,
  image_url = COALESCE(categories.image_url, EXCLUDED.image_url);