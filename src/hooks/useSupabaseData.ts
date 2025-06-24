import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';

interface Registration {
  id: string;
  full_name: string;
  mobile_number: string;
  whatsapp_number: string;
  address: string;
  panchayath_details: string;
  category: string;
  status: 'pending' | 'approved' | 'rejected';
  submitted_at: string;
  approved_at?: string;
  unique_id?: string;
  user_id?: string;
}

interface Category {
  id: string;
  name: string;
  label: string;
  actual_fee: number;
  offer_fee: number;
  has_offer: boolean;
  image_url?: string;
}

interface Panchayath {
  id: string;
  malayalam_name: string;
  english_name: string;
  pincode?: string;
  district: string;
}

interface Announcement {
  id: string;
  title: string;
  content: string;
  link?: string;
  category?: string;
  is_active: boolean;
  created_at: string;
}

interface PhotoGalleryItem {
  id: string;
  title: string;
  image_url: string;
  description?: string;
  category: string;
  uploaded_at: string;
}

interface PushNotification {
  id: string;
  title: string;
  content: string;
  target_audience: 'all' | 'category' | 'panchayath' | 'admin';
  target_value?: string;
  scheduled_at?: string;
  sent_at?: string;
  is_active: boolean;
  created_at: string;
}

export const useSupabaseData = () => {
  const [registrations, setRegistrations] = useState<Registration[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [panchayaths, setPanchayaths] = useState<Panchayath[]>([]);
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [photoGallery, setPhotoGallery] = useState<PhotoGalleryItem[]>([]);
  const [notifications, setNotifications] = useState<PushNotification[]>([]);
  const [loading, setLoading] = useState(true);
  
  const { user, isAdmin } = useAuth();
  const { toast } = useToast();

  // Fetch all data with enhanced error handling and admin access
  const fetchData = async () => {
    try {
      setLoading(true);
      
      // Fetch categories (public)
      const { data: categoriesData, error: categoriesError } = await supabase
        .from('categories')
        .select('*')
        .order('name');
      
      if (categoriesError) {
        console.error('Categories fetch error:', categoriesError);
      } else {
        setCategories(categoriesData || []);
      }

      // Fetch panchayaths (public)
      const { data: panchayathsData, error: panchayathsError } = await supabase
        .from('panchayaths')
        .select('*')
        .order('malayalam_name');
      
      if (panchayathsError) {
        console.error('Panchayaths fetch error:', panchayathsError);
      } else {
        setPanchayaths(panchayathsData || []);
      }

      // Fetch announcements (public - active only for non-admin, all for admin)
      const announcementsQuery = supabase
        .from('announcements')
        .select('*')
        .order('created_at', { ascending: false });
      
      if (!isAdmin) {
        announcementsQuery.eq('is_active', true);
      }
      
      const { data: announcementsData, error: announcementsError } = await announcementsQuery;
      
      if (announcementsError) {
        console.error('Announcements fetch error:', announcementsError);
      } else {
        setAnnouncements(announcementsData || []);
      }

      // Fetch photo gallery (public)
      const { data: galleryData, error: galleryError } = await supabase
        .from('photo_gallery')
        .select('*')
        .order('uploaded_at', { ascending: false });
      
      if (galleryError) {
        console.error('Gallery fetch error:', galleryError);
      } else {
        setPhotoGallery(galleryData || []);
      }

      if (user) {
        // Fetch registrations with enhanced admin access
        let registrationsQuery = supabase
          .from('registrations')
          .select('*')
          .order('submitted_at', { ascending: false });
        
        // Admin gets all data, users get only their own
        if (!isAdmin) {
          registrationsQuery = registrationsQuery.eq('user_id', user.id);
        }
        
        const { data: registrationsData, error: registrationsError } = await registrationsQuery;
        
        if (registrationsError) {
          console.error('Registrations fetch error:', registrationsError);
          // Don't show error to user if it's just access denied
          if (!registrationsError.message.includes('access')) {
            toast({
              title: "Error",
              description: "Failed to load registration data. Please try again.",
              variant: "destructive",
            });
          }
        } else {
          setRegistrations(registrationsData || []);
        }

        // Fetch notifications (admin only)
        if (isAdmin) {
          const { data: notificationsData, error: notificationsError } = await supabase
            .from('push_notifications')
            .select('*')
            .order('created_at', { ascending: false });
          
          if (notificationsError) {
            console.error('Notifications fetch error:', notificationsError);
          } else {
            // Filter and validate target_audience values
            const validNotifications = (notificationsData || []).filter(
              (notif): notif is PushNotification => 
                ['all', 'category', 'panchayath', 'admin'].includes(notif.target_audience)
            );
            setNotifications(validNotifications);
          }
        }
      }
    } catch (error) {
      console.error('Error fetching data:', error);
      toast({
        title: "Error",
        description: "Failed to load data. Please try again.",
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [user, isAdmin]);

  // Create registration with enhanced error handling
  const createRegistration = async (registrationData: Omit<Registration, 'id' | 'submitted_at' | 'user_id'>) => {
    if (!user) {
      toast({
        title: "Authentication Required",
        description: "Please sign in to submit a registration.",
        variant: "destructive",
      });
      return null;
    }

    try {
      const { data, error } = await supabase
        .from('registrations')
        .insert([{
          ...registrationData,
          user_id: user.id,
        }])
        .select()
        .single();

      if (error) {
        console.error('Registration creation error:', error);
        throw error;
      }

      toast({
        title: "Registration Submitted",
        description: "Your registration has been submitted successfully.",
      });

      await fetchData(); // Refresh data
      return data;
    } catch (error: any) {
      console.error('Error creating registration:', error);
      toast({
        title: "Error",
        description: error.message || "Failed to submit registration. Please try again.",
        variant: "destructive",
      });
      return null;
    }
  };

  // Update registration status (admin only) with enhanced access
  const updateRegistrationStatus = async (id: string, status: 'approved' | 'rejected', uniqueId?: string) => {
    if (!isAdmin) {
      toast({
        title: "Permission Denied",
        description: "You don't have permission to perform this action.",
        variant: "destructive",
      });
      return false;
    }

    try {
      const updateData: any = {
        status,
        approved_at: new Date().toISOString(),
      };

      if (uniqueId) {
        updateData.unique_id = uniqueId;
      }

      const { error } = await supabase
        .from('registrations')
        .update(updateData)
        .eq('id', id);

      if (error) {
        console.error('Registration update error:', error);
        throw error;
      }

      toast({
        title: "Registration Updated",
        description: `Registration has been ${status}.`,
      });

      await fetchData(); // Refresh data
      return true;
    } catch (error: any) {
      console.error('Error updating registration:', error);
      toast({
        title: "Error",
        description: error.message || "Failed to update registration. Please try again.",
        variant: "destructive",
      });
      return false;
    }
  };

  // Delete registration (admin only) with enhanced access
  const deleteRegistration = async (id: string) => {
    if (!isAdmin) {
      toast({
        title: "Permission Denied",
        description: "You don't have permission to perform this action.",
        variant: "destructive",
      });
      return false;
    }

    try {
      const { error } = await supabase
        .from('registrations')
        .delete()
        .eq('id', id);

      if (error) {
        console.error('Registration deletion error:', error);
        throw error;
      }

      toast({
        title: "Registration Deleted",
        description: "Registration has been deleted successfully.",
      });

      await fetchData(); // Refresh data
      return true;
    } catch (error: any) {
      console.error('Error deleting registration:', error);
      toast({
        title: "Error",
        description: error.message || "Failed to delete registration. Please try again.",
        variant: "destructive",
      });
      return false;
    }
  };

  // Update category image (admin only)
  const updateCategoryImage = async (categoryName: string, imageUrl: string) => {
    if (!isAdmin) {
      toast({
        title: "Permission Denied",
        description: "You don't have permission to perform this action.",
        variant: "destructive",
      });
      return false;
    }

    try {
      const { error } = await supabase
        .from('categories')
        .update({ image_url: imageUrl })
        .eq('name', categoryName);

      if (error) {
        console.error('Category image update error:', error);
        throw error;
      }

      toast({
        title: "Image Updated",
        description: "Category image has been updated successfully.",
      });

      await fetchData(); // Refresh data
      return true;
    } catch (error: any) {
      console.error('Error updating category image:', error);
      toast({
        title: "Error",
        description: error.message || "Failed to update category image. Please try again.",
        variant: "destructive",
      });
      return false;
    }
  };

  return {
    registrations,
    categories,
    panchayaths,
    announcements,
    photoGallery,
    notifications,
    loading,
    createRegistration,
    updateRegistrationStatus,
    deleteRegistration,
    updateCategoryImage,
    refreshData: fetchData,
  };
};