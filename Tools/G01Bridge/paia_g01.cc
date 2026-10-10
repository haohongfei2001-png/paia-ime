// Research extension, compiled against the exact pinned librime C++ implementation.
// All entry points run under CRimeShim's owner mutex. No engine object crosses this ABI.
#include "paia_g01.h"
#include "rime_api.h"
#include <rime/service.h>
#include <rime/context.h>
#include <rime/composition.h>
#include <rime/menu.h>
#include <rime/candidate.h>
#include <rime/gear/translator_commons.h>
#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <deque>
#include <stdexcept>
using namespace rime;
namespace {
RimeApi *api;
struct Span {
  size_t start,end,index;std::string text;Code code;
  Span(size_t a,size_t b,size_t i,std::string t,Code c={}):start(a),end(b),index(i),text(std::move(t)),code(std::move(c)){}
};
Code candidate_code(const an<Candidate>& candidate) {
  auto phrase=std::dynamic_pointer_cast<Phrase>(Candidate::GetGenuineCandidate(candidate));
  return phrase?phrase->code():Code{};
}
bool same_code(const Code& a,const Code& b){return a.size()==b.size() && std::equal(a.begin(),a.end(),b.begin());}
struct Failure {int code;};
struct Budget {
  size_t limit,used=0;
  void spend(){if(used>=limit)throw Failure{PG_INCOMPLETE};++used;}
};
struct OwnedSession {
  RimeSessionId id=0;
  ~OwnedSession(){if(id)api->destroy_session(id);}
  OwnedSession()=default;
  OwnedSession(const OwnedSession&)=delete;
  OwnedSession& operator=(const OwnedSession&)=delete;
};
auto session(uint64_t id) {
  auto s=Service::instance().GetSession(id);
  if(!s || !s->context())throw Failure{PG_INVALID};
  return s;
}
void free_list(PaiaG01List *list) {
  if(!list)return;
  free(list->raw);free(list->preview);
  if(list->items){for(size_t i=0;i<list->count;i++)free(list->items[i].text);free(list->items);}
  std::memset(list,0,sizeof(*list));
}
char *copy(const std::string& text){
  if(text.size()>65536)throw Failure{PG_INVALID};
  auto p=static_cast<char*>(std::malloc(text.size()+1));if(!p)throw std::bad_alloc();
  std::memcpy(p,text.c_str(),text.size()+1);return p;
}
void fill(PaiaG01List *out,Context *ctx,const std::vector<Span>& spans,bool complete) {
  out->raw=copy(ctx->input());out->preview=copy(ctx->GetCommitText());out->complete=complete;
  if(spans.empty())return;
  out->items=static_cast<PaiaG01Span*>(std::calloc(spans.size(),sizeof(PaiaG01Span)));
  if(!out->items)throw std::bad_alloc();out->count=spans.size();
  for(size_t i=0;i<spans.size();++i){const auto& x=spans[i];out->items[i]={x.start,x.end,x.index,copy(x.text)};}
}
std::vector<Span> selected(Context *ctx) {
  std::vector<Span> spans;size_t frontier=0;
  for(const auto& seg:ctx->composition()) {
    if(seg.start==seg.end)continue;
    if(seg.status<Segment::kSelected)throw Failure{PG_UNSUPPORTED};
    auto c=seg.GetSelectedCandidate();
    if(!c || c->start()!=frontier || c->end()<=c->start() || c->end()>ctx->input().size())throw Failure{PG_UNSUPPORTED};
    spans.push_back({c->start(),c->end(),seg.selected_index,c->text(),candidate_code(c)});
    frontier=c->end();
  }
  if(frontier!=ctx->input().size() || spans.size()>PAIA_G01_MAX_ANCHORS)throw Failure{PG_UNSUPPORTED};
  return spans;
}
an<Candidate> candidate(Context *ctx,size_t index) {
  auto& comp=ctx->composition();
  if(comp.empty() || !comp.back().menu)return nullptr;
  return comp.back().menu->GetCandidateAt(index);
}
size_t frontier(Context *ctx) {
  auto& comp=ctx->composition();return comp.empty()?0:comp.back().start;
}
bool confirmed(Context *ctx,const Span& expected) {
  for(const auto& seg:ctx->composition()) {
    if(seg.status<Segment::kSelected || seg.start!=expected.start)continue;
    auto c=seg.GetSelectedCandidate();
    return c && c->start()==expected.start && c->end()==expected.end && c->text()==expected.text &&
      (expected.code.empty() || same_code(candidate_code(c),expected.code));
  }
  return false;
}
bool choose(Context *ctx,const Span& span,Budget& budget) {
  if(frontier(ctx)!=span.start)return false;
  for(size_t i=0;;++i){
    budget.spend();auto c=candidate(ctx,i);if(!c)return false;
    if(c->start()==span.start && c->end()==span.end && c->text()==span.text && (span.code.empty() || same_code(candidate_code(c),span.code))){
      if(!ctx->Select(i))throw Failure{PG_ENGINE};
      return frontier(ctx)==span.end && confirmed(ctx,span);
    }
  }
}
void create(OwnedSession& trial,const std::string& schema,const std::map<std::string,bool>& options,const std::string& raw) {
  trial.id=api->create_session();if(!trial.id || !api->select_schema(trial.id,schema.c_str()))throw Failure{PG_ENGINE};
  auto ctx=session(trial.id)->context();
  for(const auto& option:options)ctx->set_option(option.first,option.second);
  ctx->set_option("ascii_mode",false);ctx->set_option("_no_learning",true);ctx->set_option("_auto_commit",false);
  ctx->set_input(raw);ctx->set_caret_pos(raw.size());
}
// Reconstruct genuine Sentence boundaries through actual filtered candidates in a full-raw
// scratch session. This also verifies unchanged-script decompositions rather than assuming them.
std::vector<Span> source_anchors(uint64_t id,Budget& budget) {
  auto src=session(id);auto ctx=src->context();auto fallback=selected(ctx);
  struct Part {Span span;bool genuine;};std::vector<Part> plan;bool decomposed=false;
  for(const auto& seg:ctx->composition()) {
    if(seg.start==seg.end)continue;
    auto c=seg.GetSelectedCandidate();auto genuine=Candidate::GetGenuineCandidate(c);
    auto sentence=std::dynamic_pointer_cast<Sentence>(genuine);
    if(!sentence){plan.push_back({{c->start(),c->end(),0,c->text(),candidate_code(c)},false});continue;}
    const auto& entries=sentence->components();const auto& lengths=sentence->word_lengths();
    if(entries.empty() || entries.size()!=lengths.size())throw Failure{PG_UNSUPPORTED};
    size_t offset=c->start();std::string joined;
    for(size_t i=0;i<entries.size();++i){
      if(!lengths[i] || offset+lengths[i]>c->end())throw Failure{PG_UNSUPPORTED};
      plan.push_back({{offset,offset+lengths[i],0,entries[i].text,entries[i].code},true});joined+=entries[i].text;offset+=lengths[i];
    }
    if(offset!=c->end() || joined!=genuine->text())throw Failure{PG_UNSUPPORTED};
    decomposed=true;
  }
  if(!decomposed)return fallback;
  if(plan.size()>PAIA_G01_MAX_ANCHORS)throw Failure{PG_UNSUPPORTED};
  char schema[256]={};if(!api->get_current_schema(id,schema,sizeof(schema)))throw Failure{PG_ENGINE};
  OwnedSession trial;create(trial,schema,ctx->options(),ctx->input());auto replay=session(trial.id)->context();
  std::vector<Span> spans;std::string surface;
  for(const auto& part:plan) {
    bool found=false;
    for(size_t i=0;;++i){
      budget.spend();auto c=candidate(replay,i);if(!c)break;
      if(c->start()!=part.span.start || c->end()!=part.span.end)continue;
      auto text=part.genuine?Candidate::GetGenuineCandidate(c)->text():c->text();
      if(text!=part.span.text || (!part.span.code.empty() && !same_code(candidate_code(c),part.span.code)))continue;
      spans.push_back({c->start(),c->end(),i,c->text(),candidate_code(c)});surface+=c->text();
      if(!replay->Select(i) || frontier(replay)!=part.span.end || !confirmed(replay,spans.back()))throw Failure{PG_ENGINE};
      found=true;break;
    }
    if(!found)throw Failure{PG_UNSUPPORTED};
  }
  // Cross-component filters may not be independently reproducible. Never slice their output.
  const auto verified=selected(replay);(void)verified;
  if(replay->input()!=ctx->input() || surface!=ctx->GetCommitText() || replay->GetCommitText()!=ctx->GetCommitText() ||
     !session(trial.id)->commit_text().empty())throw Failure{PG_UNSUPPORTED};
  return spans;
}
int initialize(const void *table) {
  if(table!=rime_get_api())return PG_INVALID;
  api=rime_get_api();
  if(std::strcmp(api->get_version(),"1.16.0") || !RIME_API_AVAILABLE(api,get_current_schema))return PG_INVALID;
  return PG_OK;
}
int anchors(uint64_t id,PaiaG01List *out) {
  try {auto s=session(id);if(!s->commit_text().empty())return PG_INVALID;Budget budget{PAIA_G01_MAX_SEARCH};fill(out,s->context(),source_anchors(id,budget),true);return PG_OK;}
  catch(const Failure& f){free_list(out);return f.code;}catch(...){free_list(out);return PG_ENGINE;}
}
int candidates(uint64_t id,size_t limit,PaiaG01List *out) {
  try {
    if(!limit || limit>PAIA_G01_MAX_SEARCH)return PG_INVALID;
    auto ctx=session(id)->context();std::vector<Span> spans;bool complete=false;
    for(size_t i=0;i<limit;++i){auto c=candidate(ctx,i);if(!c){complete=true;break;}spans.push_back({c->start(),c->end(),i,c->text()});}
    fill(out,ctx,spans,complete);return PG_OK;
  }catch(const Failure& f){free_list(out);return f.code;}catch(...){free_list(out);return PG_ENGINE;}
}
int prepare(uint64_t source,size_t target,const char *replacement,const char *wanted,size_t limit,PaiaG01Trial *out) {
  Budget budget{limit};
  try {
    if(!replacement || !wanted || !limit || limit>PAIA_G01_MAX_SEARCH)return PG_INVALID;
    const std::string insert(replacement),surface(wanted);
    if(insert.size()>4096 || surface.size()>65536 || !std::all_of(insert.begin(),insert.end(),[](unsigned char c){return (c>='a'&&c<='z')||c=='\''||c==' ';}))return PG_INVALID;
    auto src=session(source);auto original=src->context();
    if(!src->commit_text().empty())return PG_INVALID;
    auto locks=source_anchors(source,budget);if(target>=locks.size())return PG_INVALID;
    const auto old=locks[target];auto raw=original->input();raw.replace(old.start,old.end-old.start,insert);
    if(raw.size()>4096)return PG_INVALID;
    const size_t targetEnd=old.start+insert.size();
    const ptrdiff_t delta=static_cast<ptrdiff_t>(insert.size())-static_cast<ptrdiff_t>(old.end-old.start);
    for(size_t i=target+1;i<locks.size();++i){locks[i].start=static_cast<size_t>(static_cast<ptrdiff_t>(locks[i].start)+delta);locks[i].end=static_cast<size_t>(static_cast<ptrdiff_t>(locks[i].end)+delta);}
    char schema[256]={};if(!api->get_current_schema(source,schema,sizeof(schema)))return PG_ENGINE;
    const auto options=original->options();
    // Paths contain only observed engine candidate spans/text. No fabricated candidates/commits.
    struct Node {std::vector<Span> path;size_t next=0;};
    std::deque<Node> paths;paths.push_back({{},0});
    while(!paths.empty()) {
      budget.spend();auto node=std::move(paths.front());paths.pop_front();auto& path=node.path;OwnedSession trial;create(trial,schema,options,raw);
      auto ctx=session(trial.id)->context();bool valid=true;
      for(size_t i=0;i<target && valid;++i)valid=choose(ctx,locks[i],budget);
      for(const auto& part:path)if(valid)valid=choose(ctx,part,budget);
      if(!valid)continue;
      size_t position=frontier(ctx);std::string targetText;for(const auto& p:path)targetText+=p.text;
      if(position==targetEnd && targetText==surface) {
        for(size_t i=target+1;i<locks.size() && valid;++i)valid=choose(ctx,locks[i],budget);
        if(!valid)continue;
        auto actual=selected(ctx);std::string expected;
        for(size_t i=0;i<target;++i)expected+=locks[i].text;expected+=surface;
        for(size_t i=target+1;i<locks.size();++i)expected+=locks[i].text;
        if(ctx->input()!=raw || ctx->GetCommitText()!=expected || !session(trial.id)->commit_text().empty())throw Failure{PG_ENGINE};
        fill(&out->result,ctx,actual,true);out->session=trial.id;trial.id=0;out->examined=budget.used;out->status=PG_OK;return PG_OK;
      }
      if(position>=targetEnd || targetText.size()>=surface.size())continue;
      for(size_t index=node.next;;++index) {
        budget.spend();auto c=candidate(ctx,index);if(!c)break;
        if(c->start()!=position || c->end()<=position || c->end()>targetEnd)continue;
        auto joined=targetText+c->text();if(surface.compare(0,joined.size(),joined)!=0)continue;
        auto next=path;next.push_back({c->start(),c->end(),index,c->text(),candidate_code(c)});
        paths.push_front({path,index+1});paths.push_front({std::move(next),0});break;
      }
    }
    out->examined=budget.used;out->status=PG_CONFLICT;return out->status;
  }catch(const Failure& f){free_list(&out->result);out->examined=budget.used;out->status=f.code;return f.code;}
   catch(...){free_list(&out->result);out->examined=budget.used;out->status=PG_ENGINE;return PG_ENGINE;}
}
void free_alternatives(PaiaG01Alternatives *out) {
  if(!out)return;
  free(out->raw);
  if(out->items){for(size_t i=0;i<out->count;++i){free(out->items[i].surface);free(out->items[i].preview);}free(out->items);}
  std::memset(out,0,sizeof(*out));
}
int alternatives(uint64_t source,size_t target,const char *replacement,size_t limit,size_t maxRows,PaiaG01Alternatives *out) {
  Budget budget{limit};std::string raw;std::vector<std::pair<std::string,std::string>> rows;
  size_t outputBytes=0;int status=PG_ENGINE;
  try {
    if(!replacement || !limit || limit>PAIA_G01_MAX_SEARCH || !maxRows || maxRows>PAIA_G01_MAX_ALTERNATIVES)throw Failure{PG_INVALID};
    const std::string insert(replacement);
    if(insert.size()>4096 || !std::all_of(insert.begin(),insert.end(),[](unsigned char c){return (c>='a'&&c<='z')||c=='\''||c==' ';}))throw Failure{PG_INVALID};
    auto src=session(source);auto original=src->context();
    if(!src->commit_text().empty())throw Failure{PG_INVALID};
    auto locks=source_anchors(source,budget);if(target>=locks.size())throw Failure{PG_INVALID};
    const auto old=locks[target];raw=original->input();raw.replace(old.start,old.end-old.start,insert);
    if(raw.size()>4096)throw Failure{PG_INVALID};
    const size_t targetEnd=old.start+insert.size();
    const ptrdiff_t delta=static_cast<ptrdiff_t>(insert.size())-static_cast<ptrdiff_t>(old.end-old.start);
    for(size_t i=target+1;i<locks.size();++i){locks[i].start=static_cast<size_t>(static_cast<ptrdiff_t>(locks[i].start)+delta);locks[i].end=static_cast<size_t>(static_cast<ptrdiff_t>(locks[i].end)+delta);}
    char schema[256]={};if(!api->get_current_schema(source,schema,sizeof(schema)))throw Failure{PG_ENGINE};
    const auto options=original->options();
    struct Node {std::vector<Span> path;size_t next=0;};
    std::deque<Node> paths;paths.push_back({{},0});
    while(!paths.empty()) {
      budget.spend();auto node=std::move(paths.front());paths.pop_front();OwnedSession trial;create(trial,schema,options,raw);
      auto ctx=session(trial.id)->context();bool valid=true;
      for(size_t i=0;i<target && valid;++i)valid=choose(ctx,locks[i],budget);
      for(const auto& part:node.path)if(valid)valid=choose(ctx,part,budget);
      if(!valid)continue;
      const size_t position=frontier(ctx);std::string surface;for(const auto& part:node.path)surface+=part.text;
      if(position==targetEnd) {
        for(size_t i=target+1;i<locks.size() && valid;++i)valid=choose(ctx,locks[i],budget);
        if(!valid)continue;
        (void)selected(ctx);std::string expected;
        for(size_t i=0;i<target;++i)expected+=locks[i].text;expected+=surface;
        for(size_t i=target+1;i<locks.size();++i)expected+=locks[i].text;
        const auto preview=ctx->GetCommitText();
        if(ctx->input()!=raw || preview!=expected || !session(trial.id)->commit_text().empty())throw Failure{PG_ENGINE};
        auto row=std::make_pair(surface,preview);
        if(std::find(rows.begin(),rows.end(),row)!=rows.end())continue;
        if(rows.size()>=maxRows || surface.size()>65536 || preview.size()>65536 ||
           surface.size()+preview.size()>PAIA_G01_MAX_OUTPUT_BYTES-outputBytes)throw Failure{PG_INCOMPLETE};
        outputBytes+=surface.size()+preview.size();rows.push_back(std::move(row));continue;
      }
      if(position>=targetEnd)continue;
      if(node.path.size()>=PAIA_G01_MAX_ANCHORS)throw Failure{PG_INCOMPLETE};
      for(size_t index=node.next;;++index) {
        budget.spend();auto c=candidate(ctx,index);if(!c)break;
        if(c->start()!=position || c->end()<=position || c->end()>targetEnd)continue;
        auto next=node.path;next.push_back({c->start(),c->end(),index,c->text(),candidate_code(c)});
        paths.push_front({node.path,index+1});paths.push_front({std::move(next),0});break;
      }
    }
    status=rows.empty()?PG_CONFLICT:PG_OK;
  }catch(const Failure& f){status=f.code;}catch(...){status=PG_ENGINE;}
  out->status=status;out->examined=budget.used;
  if(status!=PG_OK && status!=PG_CONFLICT && status!=PG_INCOMPLETE)return status;
  try {
    out->raw=copy(raw);out->complete=status!=PG_INCOMPLETE;
    if(!rows.empty()){
      out->items=static_cast<PaiaG01Alternative*>(std::calloc(rows.size(),sizeof(PaiaG01Alternative)));
      if(!out->items)throw std::bad_alloc();out->count=rows.size();
      for(size_t i=0;i<rows.size();++i){out->items[i].surface=copy(rows[i].first);out->items[i].preview=copy(rows[i].second);}
    }
    return status;
  }catch(...){free_alternatives(out);out->status=PG_ENGINE;out->examined=budget.used;return PG_ENGINE;}
}

PaiaG01API extension={sizeof(PaiaG01API),PAIA_G01_ABI,initialize,anchors,candidates,prepare,free_list,alternatives,free_alternatives};
}
extern "C" __attribute__((visibility("default"))) PaiaG01API *paia_g01_get_api(){return &extension;}
