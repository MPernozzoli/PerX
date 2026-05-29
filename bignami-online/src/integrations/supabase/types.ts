export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "13.0.5"
  }
  public: {
    Tables: {
      bulk_imports: {
        Row: {
          ai_analysis: Json | null
          created_at: string
          error_message: string | null
          file_url: string
          filename: string
          id: string
          imported_policies_count: number | null
          processed_at: string | null
          status: string
          user_id: string
        }
        Insert: {
          ai_analysis?: Json | null
          created_at?: string
          error_message?: string | null
          file_url: string
          filename: string
          id?: string
          imported_policies_count?: number | null
          processed_at?: string | null
          status?: string
          user_id: string
        }
        Update: {
          ai_analysis?: Json | null
          created_at?: string
          error_message?: string | null
          file_url?: string
          filename?: string
          id?: string
          imported_policies_count?: number | null
          processed_at?: string | null
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      comments: {
        Row: {
          body: string
          created_at: string
          id: string
          parent_comment_id: string | null
          resolved: boolean | null
          target_id: string
          target_type: string
          user_id: string
          visibility: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          resolved?: boolean | null
          target_id: string
          target_type: string
          user_id: string
          visibility?: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          resolved?: boolean | null
          target_id?: string
          target_type?: string
          user_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
        ]
      }
      common_limits: {
        Row: {
          article_number: string | null
          coverage_id: string
          created_at: string
          id: string
          label: string
          on_frontespizio: boolean | null
          page_reference: string | null
          scope: string
          value: string
        }
        Insert: {
          article_number?: string | null
          coverage_id: string
          created_at?: string
          id?: string
          label: string
          on_frontespizio?: boolean | null
          page_reference?: string | null
          scope: string
          value: string
        }
        Update: {
          article_number?: string | null
          coverage_id?: string
          created_at?: string
          id?: string
          label?: string
          on_frontespizio?: boolean | null
          page_reference?: string | null
          scope?: string
          value?: string
        }
        Relationships: [
          {
            foreignKeyName: "common_limits_coverage_id_fkey"
            columns: ["coverage_id"]
            isOneToOne: false
            referencedRelation: "coverages"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_formats: {
        Row: {
          category: string
          content: string
          created_at: string
          created_by: string
          id: string
          studio_id: string
          title: string
          updated_at: string
        }
        Insert: {
          category: string
          content: string
          created_at?: string
          created_by: string
          id?: string
          studio_id: string
          title: string
          updated_at?: string
        }
        Update: {
          category?: string
          content?: string
          created_at?: string
          created_by?: string
          id?: string
          studio_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_formats_studio_id_fkey"
            columns: ["studio_id"]
            isOneToOne: false
            referencedRelation: "studios"
            referencedColumns: ["id"]
          },
        ]
      }
      companies: {
        Row: {
          aliases: string[] | null
          code: string
          created_at: string
          id: string
          name: string
        }
        Insert: {
          aliases?: string[] | null
          code: string
          created_at?: string
          id?: string
          name: string
        }
        Update: {
          aliases?: string[] | null
          code?: string
          created_at?: string
          id?: string
          name?: string
        }
        Relationships: []
      }
      coverage_items: {
        Row: {
          common_exclusions: string[] | null
          coverage_id: string
          created_at: string
          deductible_applies_to: string[] | null
          deductible_article_number: string | null
          deductible_maximum: string | null
          deductible_minimum: string | null
          deductible_page_reference: string | null
          deductible_percentage: string | null
          deductible_type: string | null
          deductible_value: string | null
          description: string | null
          exact_name: string | null
          exclusions_apply_to: string[] | null
          exclusions_article_number: string | null
          exclusions_page_reference: string | null
          guarantee_exclusions: string[] | null
          guarantee_group: string
          guarantee_name: string
          id: string
          maximum_applies_to: string[] | null
          maximum_article_number: string | null
          maximum_page_reference: string | null
          maximum_type: string | null
          maximum_value: string | null
          order_index: number
          primo_rischio_value: string | null
          value_type: string | null
        }
        Insert: {
          common_exclusions?: string[] | null
          coverage_id: string
          created_at?: string
          deductible_applies_to?: string[] | null
          deductible_article_number?: string | null
          deductible_maximum?: string | null
          deductible_minimum?: string | null
          deductible_page_reference?: string | null
          deductible_percentage?: string | null
          deductible_type?: string | null
          deductible_value?: string | null
          description?: string | null
          exact_name?: string | null
          exclusions_apply_to?: string[] | null
          exclusions_article_number?: string | null
          exclusions_page_reference?: string | null
          guarantee_exclusions?: string[] | null
          guarantee_group?: string
          guarantee_name: string
          id?: string
          maximum_applies_to?: string[] | null
          maximum_article_number?: string | null
          maximum_page_reference?: string | null
          maximum_type?: string | null
          maximum_value?: string | null
          order_index?: number
          primo_rischio_value?: string | null
          value_type?: string | null
        }
        Update: {
          common_exclusions?: string[] | null
          coverage_id?: string
          created_at?: string
          deductible_applies_to?: string[] | null
          deductible_article_number?: string | null
          deductible_maximum?: string | null
          deductible_minimum?: string | null
          deductible_page_reference?: string | null
          deductible_percentage?: string | null
          deductible_type?: string | null
          deductible_value?: string | null
          description?: string | null
          exact_name?: string | null
          exclusions_apply_to?: string[] | null
          exclusions_article_number?: string | null
          exclusions_page_reference?: string | null
          guarantee_exclusions?: string[] | null
          guarantee_group?: string
          guarantee_name?: string
          id?: string
          maximum_applies_to?: string[] | null
          maximum_article_number?: string | null
          maximum_page_reference?: string | null
          maximum_type?: string | null
          maximum_value?: string | null
          order_index?: number
          primo_rischio_value?: string | null
          value_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "coverage_items_coverage_id_fkey"
            columns: ["coverage_id"]
            isOneToOne: false
            referencedRelation: "coverages"
            referencedColumns: ["id"]
          },
        ]
      }
      coverages: {
        Row: {
          article_number: string | null
          common_exclusions: string[] | null
          common_interpretations: string[] | null
          common_notes: string[] | null
          created_at: string
          definitions: string[] | null
          guarantee: string
          id: string
          overview_text: string
          page_reference: string | null
          policy_edition_id: string
          primo_rischio_value: string | null
          value_type: string | null
        }
        Insert: {
          article_number?: string | null
          common_exclusions?: string[] | null
          common_interpretations?: string[] | null
          common_notes?: string[] | null
          created_at?: string
          definitions?: string[] | null
          guarantee?: string
          id?: string
          overview_text: string
          page_reference?: string | null
          policy_edition_id: string
          primo_rischio_value?: string | null
          value_type?: string | null
        }
        Update: {
          article_number?: string | null
          common_exclusions?: string[] | null
          common_interpretations?: string[] | null
          common_notes?: string[] | null
          created_at?: string
          definitions?: string[] | null
          guarantee?: string
          id?: string
          overview_text?: string
          page_reference?: string | null
          policy_edition_id?: string
          primo_rischio_value?: string | null
          value_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "coverages_policy_edition_id_fkey"
            columns: ["policy_edition_id"]
            isOneToOne: false
            referencedRelation: "policy_editions"
            referencedColumns: ["id"]
          },
        ]
      }
      edit_history: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          change_summary: string
          created_at: string
          diff: Json | null
          id: string
          rejection_reason: string | null
          status: string
          target_id: string
          target_type: string
          user_id: string
          visibility: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          change_summary: string
          created_at?: string
          diff?: Json | null
          id?: string
          rejection_reason?: string | null
          status?: string
          target_id: string
          target_type: string
          user_id: string
          visibility?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          change_summary?: string
          created_at?: string
          diff?: Json | null
          id?: string
          rejection_reason?: string | null
          status?: string
          target_id?: string
          target_type?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      guarantee_damage_definitions: {
        Row: {
          applies_to: string[] | null
          article_number: string | null
          coverage_item_id: string
          created_at: string
          definition_type: string
          id: string
          notes: string | null
          order_index: number | null
          page_reference: string | null
        }
        Insert: {
          applies_to?: string[] | null
          article_number?: string | null
          coverage_item_id: string
          created_at?: string
          definition_type: string
          id?: string
          notes?: string | null
          order_index?: number | null
          page_reference?: string | null
        }
        Update: {
          applies_to?: string[] | null
          article_number?: string | null
          coverage_item_id?: string
          created_at?: string
          definition_type?: string
          id?: string
          notes?: string | null
          order_index?: number | null
          page_reference?: string | null
        }
        Relationships: []
      }
      guarantee_deductibles: {
        Row: {
          applies_to: string[] | null
          article_number: string | null
          coverage_item_id: string
          created_at: string
          exact_value: string | null
          id: string
          maximum_value: string | null
          minimum_value: string | null
          notes: string | null
          on_frontespizio: boolean | null
          order_index: number | null
          page_reference: string | null
          percentage: string | null
        }
        Insert: {
          applies_to?: string[] | null
          article_number?: string | null
          coverage_item_id: string
          created_at?: string
          exact_value?: string | null
          id?: string
          maximum_value?: string | null
          minimum_value?: string | null
          notes?: string | null
          on_frontespizio?: boolean | null
          order_index?: number | null
          page_reference?: string | null
          percentage?: string | null
        }
        Update: {
          applies_to?: string[] | null
          article_number?: string | null
          coverage_item_id?: string
          created_at?: string
          exact_value?: string | null
          id?: string
          maximum_value?: string | null
          minimum_value?: string | null
          notes?: string | null
          on_frontespizio?: boolean | null
          order_index?: number | null
          page_reference?: string | null
          percentage?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "guarantee_deductibles_coverage_item_id_fkey"
            columns: ["coverage_item_id"]
            isOneToOne: false
            referencedRelation: "coverage_items"
            referencedColumns: ["id"]
          },
        ]
      }
      guarantee_exclusion_groups: {
        Row: {
          applies_to: string[] | null
          article_number: string | null
          coverage_item_id: string
          created_at: string
          exclusions: string[]
          id: string
          order_index: number | null
          page_reference: string | null
        }
        Insert: {
          applies_to?: string[] | null
          article_number?: string | null
          coverage_item_id: string
          created_at?: string
          exclusions: string[]
          id?: string
          order_index?: number | null
          page_reference?: string | null
        }
        Update: {
          applies_to?: string[] | null
          article_number?: string | null
          coverage_item_id?: string
          created_at?: string
          exclusions?: string[]
          id?: string
          order_index?: number | null
          page_reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "guarantee_exclusion_groups_coverage_item_id_fkey"
            columns: ["coverage_item_id"]
            isOneToOne: false
            referencedRelation: "coverage_items"
            referencedColumns: ["id"]
          },
        ]
      }
      guarantee_groups: {
        Row: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          name: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
        }
        Relationships: []
      }
      guarantee_maximums: {
        Row: {
          applies_to: string[] | null
          article_number: string | null
          coverage_item_id: string
          created_at: string
          exact_value: string | null
          id: string
          maximum_value: string | null
          minimum_value: string | null
          notes: string | null
          on_frontespizio: boolean | null
          order_index: number | null
          page_reference: string | null
          percentage_of_party: string | null
        }
        Insert: {
          applies_to?: string[] | null
          article_number?: string | null
          coverage_item_id: string
          created_at?: string
          exact_value?: string | null
          id?: string
          maximum_value?: string | null
          minimum_value?: string | null
          notes?: string | null
          on_frontespizio?: boolean | null
          order_index?: number | null
          page_reference?: string | null
          percentage_of_party?: string | null
        }
        Update: {
          applies_to?: string[] | null
          article_number?: string | null
          coverage_item_id?: string
          created_at?: string
          exact_value?: string | null
          id?: string
          maximum_value?: string | null
          minimum_value?: string | null
          notes?: string | null
          on_frontespizio?: boolean | null
          order_index?: number | null
          page_reference?: string | null
          percentage_of_party?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "guarantee_maximums_coverage_item_id_fkey"
            columns: ["coverage_item_id"]
            isOneToOne: false
            referencedRelation: "coverage_items"
            referencedColumns: ["id"]
          },
        ]
      }
      norm_refs: {
        Row: {
          article: string
          code: string
          comma: string | null
          id: string
          last_update: string
          links: string[] | null
          summary: string
          tags: string[] | null
          text: string
        }
        Insert: {
          article: string
          code: string
          comma?: string | null
          id?: string
          last_update?: string
          links?: string[] | null
          summary: string
          tags?: string[] | null
          text: string
        }
        Update: {
          article?: string
          code?: string
          comma?: string | null
          id?: string
          last_update?: string
          links?: string[] | null
          summary?: string
          tags?: string[] | null
          text?: string
        }
        Relationships: []
      }
      policies: {
        Row: {
          code: string
          company_id: string
          created_at: string
          default_guarantee: string
          description: string
          id: string
          name: string
          tags: string[] | null
          type: string
        }
        Insert: {
          code: string
          company_id: string
          created_at?: string
          default_guarantee?: string
          description: string
          id?: string
          name: string
          tags?: string[] | null
          type: string
        }
        Update: {
          code?: string
          company_id?: string
          created_at?: string
          default_guarantee?: string
          description?: string
          id?: string
          name?: string
          tags?: string[] | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "policies_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      policy_editions: {
        Row: {
          canonical_group_id: string | null
          code: string
          created_at: string
          edition_label: string | null
          id: string
          pdf_sha256: string | null
          pdf_url: string | null
          policy_id: string
          status: string
          year: number
        }
        Insert: {
          canonical_group_id?: string | null
          code: string
          created_at?: string
          edition_label?: string | null
          id?: string
          pdf_sha256?: string | null
          pdf_url?: string | null
          policy_id: string
          status?: string
          year: number
        }
        Update: {
          canonical_group_id?: string | null
          code?: string
          created_at?: string
          edition_label?: string | null
          id?: string
          pdf_sha256?: string | null
          pdf_url?: string | null
          policy_id?: string
          status?: string
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "policy_editions_policy_id_fkey"
            columns: ["policy_id"]
            isOneToOne: false
            referencedRelation: "policies"
            referencedColumns: ["id"]
          },
        ]
      }
      post_comments: {
        Row: {
          author_id: string
          content: string
          created_at: string
          id: string
          post_id: string
        }
        Insert: {
          author_id: string
          content: string
          created_at?: string
          id?: string
          post_id: string
        }
        Update: {
          author_id?: string
          content?: string
          created_at?: string
          id?: string
          post_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "post_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "studio_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      post_likes: {
        Row: {
          created_at: string
          id: string
          post_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          post_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "post_likes_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "studio_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          auth_provider: string | null
          created_at: string
          default_company: string | null
          default_guarantee: string | null
          email: string
          id: string
          name: string
        }
        Insert: {
          auth_provider?: string | null
          created_at?: string
          default_company?: string | null
          default_guarantee?: string | null
          email: string
          id: string
          name: string
        }
        Update: {
          auth_provider?: string | null
          created_at?: string
          default_company?: string | null
          default_guarantee?: string | null
          email?: string
          id?: string
          name?: string
        }
        Relationships: []
      }
      sections: {
        Row: {
          article_number: string | null
          coverage_id: string
          created_at: string
          definition: string
          definition_article_number: string | null
          definition_page_reference: string | null
          deroga_percentage: number | null
          determinazione: string[] | null
          emoji: string | null
          exact_name: string | null
          exclusions: string[] | null
          id: string
          links_to_common_limits: string[] | null
          notes: string[] | null
          page_reference: string | null
          party: string
          primo_rischio_value: string | null
          value_type: string | null
        }
        Insert: {
          article_number?: string | null
          coverage_id: string
          created_at?: string
          definition: string
          definition_article_number?: string | null
          definition_page_reference?: string | null
          deroga_percentage?: number | null
          determinazione?: string[] | null
          emoji?: string | null
          exact_name?: string | null
          exclusions?: string[] | null
          id?: string
          links_to_common_limits?: string[] | null
          notes?: string[] | null
          page_reference?: string | null
          party: string
          primo_rischio_value?: string | null
          value_type?: string | null
        }
        Update: {
          article_number?: string | null
          coverage_id?: string
          created_at?: string
          definition?: string
          definition_article_number?: string | null
          definition_page_reference?: string | null
          deroga_percentage?: number | null
          determinazione?: string[] | null
          emoji?: string | null
          exact_name?: string | null
          exclusions?: string[] | null
          id?: string
          links_to_common_limits?: string[] | null
          notes?: string[] | null
          page_reference?: string | null
          party?: string
          primo_rischio_value?: string | null
          value_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sections_coverage_id_fkey"
            columns: ["coverage_id"]
            isOneToOne: false
            referencedRelation: "coverages"
            referencedColumns: ["id"]
          },
        ]
      }
      studio_members: {
        Row: {
          companies: string[] | null
          id: string
          joined_at: string
          role: Database["public"]["Enums"]["studio_role"]
          studio_id: string
          user_id: string
        }
        Insert: {
          companies?: string[] | null
          id?: string
          joined_at?: string
          role?: Database["public"]["Enums"]["studio_role"]
          studio_id: string
          user_id: string
        }
        Update: {
          companies?: string[] | null
          id?: string
          joined_at?: string
          role?: Database["public"]["Enums"]["studio_role"]
          studio_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "studio_members_studio_id_fkey"
            columns: ["studio_id"]
            isOneToOne: false
            referencedRelation: "studios"
            referencedColumns: ["id"]
          },
        ]
      }
      studio_posts: {
        Row: {
          author_id: string
          comments_count: number | null
          content: string
          created_at: string
          id: string
          is_locked: boolean | null
          likes_count: number | null
          studio_id: string
          tagged_users: string[] | null
          updated_at: string
        }
        Insert: {
          author_id: string
          comments_count?: number | null
          content: string
          created_at?: string
          id?: string
          is_locked?: boolean | null
          likes_count?: number | null
          studio_id: string
          tagged_users?: string[] | null
          updated_at?: string
        }
        Update: {
          author_id?: string
          comments_count?: number | null
          content?: string
          created_at?: string
          id?: string
          is_locked?: boolean | null
          likes_count?: number | null
          studio_id?: string
          tagged_users?: string[] | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "studio_posts_studio_id_fkey"
            columns: ["studio_id"]
            isOneToOne: false
            referencedRelation: "studios"
            referencedColumns: ["id"]
          },
        ]
      }
      studio_templates: {
        Row: {
          body_template: string
          id: string
          kind: string
          studio_id: string
          tags: string[] | null
          title: string
          updated_at: string
        }
        Insert: {
          body_template: string
          id?: string
          kind: string
          studio_id: string
          tags?: string[] | null
          title: string
          updated_at?: string
        }
        Update: {
          body_template?: string
          id?: string
          kind?: string
          studio_id?: string
          tags?: string[] | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "studio_templates_studio_id_fkey"
            columns: ["studio_id"]
            isOneToOne: false
            referencedRelation: "studios"
            referencedColumns: ["id"]
          },
        ]
      }
      studios: {
        Row: {
          created_at: string
          description: string | null
          id: string
          invitation_code: string
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          invitation_code?: string
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          invitation_code?: string
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      user_policy_interactions: {
        Row: {
          active_guarantees: Json | null
          bookmarked: boolean | null
          id: string
          last_viewed: string
          policy_edition_id: string
          policy_id: string
          preferences_updated_at: string | null
          selected_guarantee_group: string | null
          user_id: string
          view_count: number | null
        }
        Insert: {
          active_guarantees?: Json | null
          bookmarked?: boolean | null
          id?: string
          last_viewed?: string
          policy_edition_id: string
          policy_id: string
          preferences_updated_at?: string | null
          selected_guarantee_group?: string | null
          user_id: string
          view_count?: number | null
        }
        Update: {
          active_guarantees?: Json | null
          bookmarked?: boolean | null
          id?: string
          last_viewed?: string
          policy_edition_id?: string
          policy_id?: string
          preferences_updated_at?: string | null
          selected_guarantee_group?: string | null
          user_id?: string
          view_count?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "user_policy_interactions_policy_edition_id_fkey"
            columns: ["policy_edition_id"]
            isOneToOne: false
            referencedRelation: "policy_editions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_policy_interactions_policy_id_fkey"
            columns: ["policy_id"]
            isOneToOne: false
            referencedRelation: "policies"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      generate_random_code: {
        Args: { length?: number }
        Returns: string
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      has_studio_role: {
        Args: {
          _role: Database["public"]["Enums"]["studio_role"]
          _studio_id: string
          _user_id: string
        }
        Returns: boolean
      }
      is_studio_member: {
        Args: { _studio_id: string; _user_id: string }
        Returns: boolean
      }
    }
    Enums: {
      app_role: "admin" | "moderator" | "user"
      studio_role: "admin" | "team_leader" | "moderator" | "member"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "moderator", "user"],
      studio_role: ["admin", "team_leader", "moderator", "member"],
    },
  },
} as const
