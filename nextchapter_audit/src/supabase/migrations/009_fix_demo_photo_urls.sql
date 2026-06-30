-- ============================================================================
-- Batch FIX — Replace broken demo photo URL
-- ============================================================================
-- One of the Unsplash URLs seeded in 007 (photo-1546961342-1e3c5f6f7b8a, used
-- as Sarah's third photo) now returns 404. The rest of the Unsplash URLs are
-- still served fine. We just swap the broken URL with a working one so the
-- profile detail carousel stops showing a placeholder for Sarah.
--
-- Safe to run multiple times: idempotent UPDATE keyed on the broken URL.
-- Touches no other rows.
-- ============================================================================

update public.profile_photos
   set display_url = 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=900&q=80',
       storage_path = 'demo/sarah-3.jpg'
 where display_url = 'https://images.unsplash.com/photo-1546961342-1e3c5f6f7b8a?w=900&q=80';
