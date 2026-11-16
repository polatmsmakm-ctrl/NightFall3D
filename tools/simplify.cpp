// Quadric edge-collapse simplifier for a welded, manifold triangle mesh, with a triangle budget
// per region (the head, the hands and the feet keep their own, as tools/rig_character.py asks)
// and a per-vertex importance that keeps detail where the eye goes.
//
//   in : int32 nv, nf, nr ; float64 maxlen ; int32 target[nr] ; float64 P[nv*3] ; int32 F[nf*3] ;
//        uint8 region[nf] ; float32 weight[nv] ; uint8 soft[nv]
//        (soft: hair. Between two soft vertices a collapse may pinch a strand shut - the two faces
//         left back to back are dropped - so loose strands thin out and close instead of holding
//         three triangles round every one of them for ever)
//        (maxlen: no collapse may leave an edge longer than this - limbs need rings to bend at)
//   out: int32 nv, nf ; float64 P[nv*3] ; int32 F[nf*3]
//
// g++ -O2 -o simplify simplify.cpp
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <vector>
#include <queue>
#include <algorithm>

struct V3 { double x, y, z; };
static inline V3 sub(V3 a, V3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
static inline V3 cross(V3 a, V3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
static inline double dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline double len(V3 a) { return std::sqrt(dot(a, a)); }

struct Q { double a[10]; };   // xx xy xz xw yy yz yw zz zw ww
static inline void qadd(Q& q, const Q& o) { for (int i = 0; i < 10; i++) q.a[i] += o.a[i]; }
static inline double qerr(const Q& q, V3 p) {
    const double* a = q.a;
    return a[0] * p.x * p.x + 2 * a[1] * p.x * p.y + 2 * a[2] * p.x * p.z + 2 * a[3] * p.x
         + a[4] * p.y * p.y + 2 * a[5] * p.y * p.z + 2 * a[6] * p.y
         + a[7] * p.z * p.z + 2 * a[8] * p.z + a[9];
}
static bool qsolve(const Q& q, V3& out) {
    const double* a = q.a;
    double m00 = a[0], m01 = a[1], m02 = a[2], m11 = a[4], m12 = a[5], m22 = a[7];
    double det = m00 * (m11 * m22 - m12 * m12) - m01 * (m01 * m22 - m12 * m02) + m02 * (m01 * m12 - m11 * m02);
    double scale = std::fabs(m00) + std::fabs(m11) + std::fabs(m22);
    if (std::fabs(det) < 1e-10 * scale * scale * scale + 1e-300) return false;
    double bx = -a[3], by = -a[6], bz = -a[8];
    out.x = (bx * (m11 * m22 - m12 * m12) - m01 * (by * m22 - m12 * bz) + m02 * (by * m12 - m11 * bz)) / det;
    out.y = (m00 * (by * m22 - m12 * bz) - bx * (m01 * m22 - m12 * m02) + m02 * (m01 * bz - by * m02)) / det;
    out.z = (m00 * (m11 * bz - by * m12) - m01 * (m01 * bz - by * m02) + bx * (m01 * m12 - m11 * m02)) / det;
    return true;
}

struct Item { double c; int a, b; unsigned va, vb; };
struct Cmp { bool operator()(const Item& x, const Item& y) const { return x.c > y.c; } };

int nv, nf, nr;
std::vector<V3> P;
std::vector<int> F;
std::vector<uint8_t> region, dead;
std::vector<Q> quad;
std::vector<std::vector<int>> vf;
std::vector<unsigned> ver;
std::vector<int> target, count_;
std::priority_queue<Item, std::vector<Item>, Cmp> heap;

static void place(int a, int b, V3& p, double& c) {
    Q q = quad[a]; qadd(q, quad[b]);
    V3 pa = P[a], pb = P[b], pm = {(pa.x + pb.x) / 2, (pa.y + pb.y) / 2, (pa.z + pb.z) / 2};
    double L = len(sub(pa, pb));
    V3 s;
    if (qsolve(q, s) && len(sub(s, pm)) < 2.0 * L) { p = s; c = qerr(q, s); }
    else {
        double ca = qerr(q, pa), cb = qerr(q, pb), cm = qerr(q, pm);
        if (cm <= ca && cm <= cb) { p = pm; c = cm; } else if (ca <= cb) { p = pa; c = ca; } else { p = pb; c = cb; }
    }
    if (c < 0) c = 0;
    c += 1e-9 * L * L;                 // on flat ground, take the short edges first
}
static void push(int a, int b) {
    V3 p; double c; place(a, b, p, c);
    heap.push({c, a, b, ver[a], ver[b]});
}

int main(int argc, char** argv) {
    FILE* fi = fopen(argv[1], "rb");
    int32_t h[3]; if (fread(h, 4, 3, fi) != 3) return 1;
    nv = h[0]; nf = h[1]; nr = h[2];
    double maxlen; if (fread(&maxlen, 8, 1, fi) != 1) return 1;
    target.resize(nr); if (fread(target.data(), 4, nr, fi) != (size_t)nr) return 1;
    P.resize(nv); F.resize((size_t)nf * 3); region.resize(nf); std::vector<float> w(nv);
    if (fread(P.data(), 8, (size_t)nv * 3, fi) != (size_t)nv * 3) return 1;
    if (fread(F.data(), 4, F.size(), fi) != F.size()) return 1;
    if (fread(region.data(), 1, nf, fi) != (size_t)nf) return 1;
    if (fread(w.data(), 4, nv, fi) != (size_t)nv) return 1;
    std::vector<uint8_t> soft(nv); if (fread(soft.data(), 1, nv, fi) != (size_t)nv) return 1;
    fclose(fi);
    dead.assign(nf, 0); quad.assign(nv, Q{{0, 0, 0, 0, 0, 0, 0, 0, 0, 0}}); vf.resize(nv); ver.assign(nv, 0);
    count_.assign(nr, 0);
    for (int f = 0; f < nf; f++) {
        int* t = &F[(size_t)f * 3];
        count_[region[f]]++;
        V3 n = cross(sub(P[t[1]], P[t[0]]), sub(P[t[2]], P[t[0]]));
        double l = len(n);
        for (int k = 0; k < 3; k++) vf[t[k]].push_back(f);
        if (l < 1e-300) continue;
        n = {n.x / l, n.y / l, n.z / l};
        double d = -dot(n, P[t[0]]), ar = l * 0.5;
        Q q = {{n.x * n.x, n.x * n.y, n.x * n.z, n.x * d, n.y * n.y, n.y * n.z, n.y * d, n.z * n.z, n.z * d, d * d}};
        for (int k = 0; k < 3; k++) {
            double s = ar * w[t[k]];
            for (int i = 0; i < 10; i++) quad[t[k]].a[i] += q.a[i] * s;
        }
    }
    for (int f = 0; f < nf; f++) {
        int* t = &F[(size_t)f * 3];
        for (int k = 0; k < 3; k++) { int a = t[k], b = t[(k + 1) % 3]; if (a < b) push(a, b); }
    }
    std::vector<int> ring, common;
    long done = 0, rejected = 0;
    while (!heap.empty()) {
        bool open = false;
        for (int r = 0; r < nr; r++) if (count_[r] > target[r]) open = true;
        if (!open) break;
        Item it = heap.top(); heap.pop();
        int a = it.a, b = it.b;
        if (ver[a] != it.va || ver[b] != it.vb) continue;
        // the faces on the edge, and the link condition (keeps the surface manifold)
        int shared[4], ns = 0, opp[4];
        for (int f : vf[a]) {
            int* t = &F[(size_t)f * 3];
            for (int k = 0; k < 3; k++) if (t[k] == b) {
                if (ns < 4) { shared[ns] = f; opp[ns] = t[0] + t[1] + t[2] - a - b; }
                ns++;
            }
        }
        if (ns != 2) { rejected++; continue; }
        int need[8] = {0, 0, 0, 0, 0, 0, 0, 0};
        need[region[shared[0]]]++; need[region[shared[1]]]++;
        bool ok = true;
        for (int r = 0; r < nr && r < 8; r++) if (need[r] && count_[r] - need[r] < target[r]) ok = false;
        if (!ok) continue;
        ring.clear(); common.clear();
        for (int f : vf[a]) { int* t = &F[(size_t)f * 3]; for (int k = 0; k < 3; k++) if (t[k] != a) ring.push_back(t[k]); }
        std::sort(ring.begin(), ring.end()); ring.erase(std::unique(ring.begin(), ring.end()), ring.end());
        for (int f : vf[b]) { int* t = &F[(size_t)f * 3]; for (int k = 0; k < 3; k++) if (t[k] != b && std::binary_search(ring.begin(), ring.end(), t[k])) common.push_back(t[k]); }
        std::sort(common.begin(), common.end()); common.erase(std::unique(common.begin(), common.end()), common.end());
        bool pinch = common.size() != 2;
        if (pinch && !(soft[a] && soft[b])) { rejected++; continue; }
        V3 p; double c; place(a, b, p, c);
        // no face may turn over or shrink to a sliver
        for (int pass = 0; pass < 2 && ok; pass++) {
            int v = pass ? b : a;
            for (int f : vf[v]) {
                if (f == shared[0] || f == shared[1]) continue;
                int* t = &F[(size_t)f * 3];
                V3 q[3], o[3];
                for (int k = 0; k < 3; k++) { o[k] = P[t[k]]; q[k] = (t[k] == v) ? p : P[t[k]]; }
                V3 n0 = cross(sub(o[1], o[0]), sub(o[2], o[0])), n1 = cross(sub(q[1], q[0]), sub(q[2], q[0]));
                double l0 = len(n0), l1 = len(n1);
                if (l1 < 1e-14) { ok = false; break; }
                if (l0 > 1e-14 && dot(n0, n1) < 0.25 * l0 * l1) { ok = false; break; }
                double e = std::max(len(sub(q[1], q[0])), std::max(len(sub(q[2], q[1])), len(sub(q[0], q[2]))));
                if (l1 < 0.02 * e * e) { ok = false; break; }           // needle
                if (e > maxlen) { ok = false; break; }                  // too long to bend
            }
        }
        if (!ok) { rejected++; continue; }
        // collapse b into a
        for (int s = 0; s < 2; s++) { dead[shared[s]] = 1; count_[region[shared[s]]]--; }
        for (int s = 0; s < 2; s++) {
            int o = opp[s];
            auto& l = vf[o]; l.erase(std::remove(l.begin(), l.end(), shared[s]), l.end());
            ver[o]++;
        }
        std::vector<int> keep;
        for (int f : vf[a]) if (!dead[f]) keep.push_back(f);
        for (int f : vf[b]) if (!dead[f]) { int* t = &F[(size_t)f * 3]; for (int k = 0; k < 3; k++) if (t[k] == b) t[k] = a; keep.push_back(f); }
        vf[a].swap(keep); vf[b].clear(); vf[b].shrink_to_fit();
        P[a] = p; qadd(quad[a], quad[b]); ver[a]++; ver[b]++;
        if (pinch) {                                          // faces now lying on each other go, both of them
            std::vector<int>& l = vf[a];
            for (size_t i = 0; i < l.size(); i++) {
                if (dead[l[i]]) continue;
                int* t = &F[(size_t)l[i] * 3];
                int x = -1, y = -1;
                for (int k = 0; k < 3; k++) if (t[k] == a) { x = t[(k + 1) % 3]; y = t[(k + 2) % 3]; }
                for (size_t j = i + 1; j < l.size(); j++) {
                    if (dead[l[j]]) continue;
                    int* u = &F[(size_t)l[j] * 3];
                    int x2 = -1, y2 = -1;
                    for (int k = 0; k < 3; k++) if (u[k] == a) { x2 = u[(k + 1) % 3]; y2 = u[(k + 2) % 3]; }
                    if (x2 == y && y2 == x) {                 // same triangle, facing the other way
                        dead[l[i]] = dead[l[j]] = 1; count_[region[l[i]]]--; count_[region[l[j]]]--;
                        for (int v : {x, y}) { auto& m = vf[v]; m.erase(std::remove_if(m.begin(), m.end(), [&](int f) { return f == l[i] || f == l[j]; }), m.end()); ver[v]++; }
                        break;
                    } else if (x2 == x && y2 == y) {          // an exact double: one is enough
                        dead[l[j]] = 1; count_[region[l[j]]]--;
                        for (int v : {x, y}) { auto& m = vf[v]; m.erase(std::remove(m.begin(), m.end(), l[j]), m.end()); ver[v]++; }
                    }
                }
            }
            l.erase(std::remove_if(l.begin(), l.end(), [&](int f) { return dead[f]; }), l.end());
        }
        ring.clear();
        for (int f : vf[a]) { int* t = &F[(size_t)f * 3]; for (int k = 0; k < 3; k++) if (t[k] != a) ring.push_back(t[k]); }
        std::sort(ring.begin(), ring.end()); ring.erase(std::unique(ring.begin(), ring.end()), ring.end());
        for (int v : ring) push(std::min(a, v), std::max(a, v));
        for (int s = 0; s < 2; s++) {                         // the two far corners lost a face: their other edges changed too
            int o = opp[s];
            for (int f : vf[o]) { int* t = &F[(size_t)f * 3]; for (int k = 0; k < 3; k++) if (t[k] != o && t[k] != a) push(std::min(o, t[k]), std::max(o, t[k])); }
        }
        done++;
    }
    std::vector<int> remap(nv, -1); int mv = 0, mf = 0;
    for (int f = 0; f < nf; f++) if (!dead[f]) { mf++; for (int k = 0; k < 3; k++) { int v = F[(size_t)f * 3 + k]; if (remap[v] < 0) remap[v] = mv++; } }
    FILE* fo = fopen(argv[2], "wb");
    int32_t oh[2] = {mv, mf}; fwrite(oh, 4, 2, fo);
    std::vector<V3> OP(mv);
    for (int v = 0; v < nv; v++) if (remap[v] >= 0) OP[remap[v]] = P[v];
    fwrite(OP.data(), 8, (size_t)mv * 3, fo);
    for (int f = 0; f < nf; f++) if (!dead[f]) { int32_t t[3]; for (int k = 0; k < 3; k++) t[k] = remap[F[(size_t)f * 3 + k]]; fwrite(t, 4, 3, fo); }
    fclose(fo);
    fprintf(stderr, "collapses %ld, refused %ld, left:", done, rejected);
    for (int r = 0; r < nr; r++) fprintf(stderr, " %d", count_[r]);
    fprintf(stderr, "\n");
    return 0;
}
