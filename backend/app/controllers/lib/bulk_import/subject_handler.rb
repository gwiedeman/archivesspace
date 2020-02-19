require_relative 'handler'
require_relative '../../../model/subject'
require_relative 'bulk_import_mixins'
include CrudHelpers

  class SubjectHandler < Handler

    def initialize(current_user)
      super
      @subject_term_types = CvList.new('subject_term_type', @current_user)
      @subject_sources = CvList.new('subject_source', @current_user)
      @subjects = {} # will track both confirmed ids, and newly created ones.
    end


    def renew
      clear(@subject_term_types)
      clear(@subject_sources)
      @subjects = {}
    end

    def key_for(subject)
      key = "#{subject[:term]} #{subject[:source]}: #{subject[:type]}"
      key
    end
    def build(id, term, type, source)
      type = type.nil? ? 'topical' : @subject_term_types.value(type)
      source = source.nil? ? 'ingest' : @subject_sources.value(source)
      {
        :id => id,
        :term =>  term || (id ? I18n.t('bulk_import.unfound_id', :id => id, :type => 'subject') : nil),
        :type =>  type,
        :source => source,
        :id_but_no_term => id && !term
      }
    end
 
    def get_or_create(id, term, type, source, repo_id, report)
      subject = build(id, term, type, source)
      subject_key = key_for(subject)
      if !(subj = stored(@subjects, subject[:id], subject_key))
        unless subject[:id].nil?
          begin
            subj = Subject.get_or_die(Integer(subject[:id]))
          rescue Exception => e
             if e.message != 'RecordNotFound'
               raise BulkImportException.new( I18n.t('bulk_import.error.no_create', :why => e.message))
             else
              raise e
             end
          end
        end
        begin
          if !subj
            begin
              subj = get_db_subj(subject)
            rescue Exception => e
              if e.is_a?(BulkImportDisambigException)
                subject[:term] = subject[:term] + DISAMB_STR
                report.add_info(I18n.t('bulk_import.warn.disam', :name => subject[:term]))
              else
                raise e
              end
            end
          end
          if !subj
            subj = create_subj(subject)
            report.add_info(I18n.t('bulk_import.created', :what =>"#{I18n.t('bulk_import.subj')}[#{subject[:term]}]", :id => subj.uri))
          end
        rescue Exception => e
          Log.error(e.backtrace)
          raise BulkImportException.new( I18n.t('bulk_import.error.no_create', :why => e.message))
        end
        if subj
          if subj[:id_but_no_term]
            @subjects[subject[:id].to_s] = subj
          else
            @subjects[subj.id.to_s] = subj
          end
          @subjects[subject_key] = subj
        end
      end
      subj
    end

    def create_subj(subject)
      begin
        term = JSONModel(:term).new._always_valid!
        term.term =  subject[:term]
        term.term_type = subject[:type]
        term.vocabulary = '/vocabularies/1'  # we're making a gross assumption here
        subj = JSONModel(:subject).new._always_valid!
        subj.terms.push term
        subj.source = subject[:source]
        subj.vocabulary = '/vocabularies/1'  # we're making a gross assumption here
        subj= save(subj, Subject)
      rescue Exception => e
        raise BulkImportException.new(I18n.t('bulk_import.error.no_create',:why => e.message))
      end
      subj
    end   

    def get_db_subj(subject)
      s_params = {}
      s_params[:q] = "title:\"#{subject[:term]}\" AND term_type_enum_s:\"#{subject[:type]}\" AND source_enum_s:\"#{subject[:source]}\""
      ret_subj = search(nil, s_params, :subject, 'subject',"title:#{subject[:term]}" )
    end
  end