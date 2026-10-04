"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";

export type PersonaDimension = "brain" | "communication" | "tech" | "execution" | "all";

interface DigitalTwinAvatar3DProps {
  activeDimension: PersonaDimension;
  onSelectDimension: (dim: PersonaDimension) => void;
  ruleStats?: {
    ironLaws: number;
    communication: number;
    tech: number;
    execution: number;
  };
}

export default function DigitalTwinAvatar3D({
  activeDimension,
  onSelectDimension,
  ruleStats = { ironLaws: 6, communication: 3, tech: 8, execution: 5 },
}: DigitalTwinAvatar3DProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [hoveredNode, setHoveredNode] = useState<PersonaDimension | null>(null);
  const [isRotating, setIsRotating] = useState(true);

  // References for animation
  const sceneRef = useRef<THREE.Scene | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const avatarGroupRef = useRef<THREE.Group | null>(null);
  const nodesRef = useRef<Record<string, THREE.Mesh>>({});
  const ringsRef = useRef<THREE.Group[]>([]);
  const particlesRef = useRef<THREE.Points | null>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    // 1. Scene & Camera Setup
    const width = container.clientWidth;
    const height = container.clientHeight || 520;

    const scene = new THREE.Scene();
    sceneRef.current = scene;

    const camera = new THREE.PerspectiveCamera(45, width / height, 0.1, 100);
    camera.position.set(0, 1.2, 5.2);

    // 2. WebGL Renderer
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.2;
    rendererRef.current = renderer;

    container.appendChild(renderer.domElement);

    // 3. Lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.8);
    scene.add(ambientLight);

    const purpleLight = new THREE.PointLight(0xa855f7, 2.5, 10);
    purpleLight.position.set(-2, 3, 2);
    scene.add(purpleLight);

    const cyanLight = new THREE.PointLight(0x06b6d4, 2.5, 10);
    cyanLight.position.set(2, -1, 2);
    scene.add(cyanLight);

    const topLight = new THREE.DirectionalLight(0xffffff, 1.2);
    topLight.position.set(0, 6, 3);
    scene.add(topLight);

    // 4. Avatar Main Group
    const avatarGroup = new THREE.Group();
    avatarGroup.position.set(0, -0.6, 0);
    avatarGroupRef.current = avatarGroup;
    scene.add(avatarGroup);

    // Materials
    const holographicWireMat = new THREE.MeshStandardMaterial({
      color: 0x8b5cf6,
      wireframe: true,
      transparent: true,
      opacity: 0.35,
      roughness: 0.2,
      metalness: 0.8,
    });

    const holographicGlowMat = new THREE.MeshStandardMaterial({
      color: 0x3b82f6,
      roughness: 0.3,
      metalness: 0.9,
      transparent: true,
      opacity: 0.45,
    });

    const nodeGlowMats: Record<string, THREE.MeshStandardMaterial> = {
      brain: new THREE.MeshStandardMaterial({
        color: 0xa855f7,
        emissive: 0xa855f7,
        emissiveIntensity: 1.8,
        roughness: 0.1,
      }),
      communication: new THREE.MeshStandardMaterial({
        color: 0x06b6d4,
        emissive: 0x06b6d4,
        emissiveIntensity: 1.8,
        roughness: 0.1,
      }),
      tech: new THREE.MeshStandardMaterial({
        color: 0xf59e0b,
        emissive: 0xf59e0b,
        emissiveIntensity: 1.8,
        roughness: 0.1,
      }),
      execution: new THREE.MeshStandardMaterial({
        color: 0x10b981,
        emissive: 0x10b981,
        emissiveIntensity: 1.8,
        roughness: 0.1,
      }),
    };

    // ── Humanoid Geometry Assembly ───────────────────────────────────────
    // Head
    const headGeo = new THREE.IcosahedronGeometry(0.38, 2);
    const head = new THREE.Mesh(headGeo, holographicWireMat);
    head.position.set(0, 2.7, 0);
    avatarGroup.add(head);

    // Inner Brain Core Node (大脑/铁律)
    const brainNodeGeo = new THREE.SphereGeometry(0.18, 16, 16);
    const brainNode = new THREE.Mesh(brainNodeGeo, nodeGlowMats.brain);
    brainNode.position.set(0, 2.72, 0);
    brainNode.userData = { dimension: "brain" };
    avatarGroup.add(brainNode);
    nodesRef.current.brain = brainNode;

    // Neck / Vocal Tract (咽喉/沟通)
    const neckGeo = new THREE.CylinderGeometry(0.14, 0.16, 0.28, 12);
    const neck = new THREE.Mesh(neckGeo, holographicGlowMat);
    neck.position.set(0, 2.32, 0);
    avatarGroup.add(neck);

    const voiceNodeGeo = new THREE.SphereGeometry(0.1, 16, 16);
    const voiceNode = new THREE.Mesh(voiceNodeGeo, nodeGlowMats.communication);
    voiceNode.position.set(0, 2.32, 0.12);
    voiceNode.userData = { dimension: "communication" };
    avatarGroup.add(voiceNode);
    nodesRef.current.communication = voiceNode;

    // Torso / Chest (胸腔)
    const chestGeo = new THREE.CylinderGeometry(0.48, 0.38, 0.72, 16);
    const chest = new THREE.Mesh(chestGeo, holographicWireMat);
    chest.position.set(0, 1.85, 0);
    avatarGroup.add(chest);

    // Heart / Tech Core Node (核心/技术架构)
    const heartNodeGeo = new THREE.OctahedronGeometry(0.16, 1);
    const heartNode = new THREE.Mesh(heartNodeGeo, nodeGlowMats.tech);
    heartNode.position.set(0, 1.9, 0.1);
    heartNode.userData = { dimension: "tech" };
    avatarGroup.add(heartNode);
    nodesRef.current.tech = heartNode;

    // Abdomen & Spine
    const spineGeo = new THREE.CylinderGeometry(0.32, 0.38, 0.5, 12);
    const spine = new THREE.Mesh(spineGeo, holographicGlowMat);
    spine.position.set(0, 1.3, 0);
    avatarGroup.add(spine);

    // Pelvis
    const pelvisGeo = new THREE.CylinderGeometry(0.38, 0.3, 0.32, 12);
    const pelvis = new THREE.Mesh(pelvisGeo, holographicWireMat);
    pelvis.position.set(0, 0.95, 0);
    avatarGroup.add(pelvis);

    // Shoulders
    const shoulderL = new THREE.Mesh(new THREE.SphereGeometry(0.16, 12, 12), holographicGlowMat);
    shoulderL.position.set(-0.64, 2.1, 0);
    const shoulderR = new THREE.Mesh(new THREE.SphereGeometry(0.16, 12, 12), holographicGlowMat);
    shoulderR.position.set(0.64, 2.1, 0);
    avatarGroup.add(shoulderL, shoulderR);

    // Arms & Hands (执行端)
    const armL = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.08, 0.9, 8), holographicWireMat);
    armL.position.set(-0.76, 1.6, 0.05);
    armL.rotation.z = 0.25;
    const armR = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.08, 0.9, 8), holographicWireMat);
    armR.position.set(0.76, 1.6, 0.05);
    armR.rotation.z = -0.25;
    avatarGroup.add(armL, armR);

    const handNodeGeo = new THREE.SphereGeometry(0.12, 16, 16);
    const handNodeL = new THREE.Mesh(handNodeGeo, nodeGlowMats.execution);
    handNodeL.position.set(-0.9, 1.15, 0.1);
    handNodeL.userData = { dimension: "execution" };
    const handNodeR = new THREE.Mesh(handNodeGeo, nodeGlowMats.execution);
    handNodeR.position.set(0.9, 1.15, 0.1);
    handNodeR.userData = { dimension: "execution" };
    avatarGroup.add(handNodeL, handNodeR);
    nodesRef.current.execution = handNodeR;

    // Legs
    const legL = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.09, 1.4, 8), holographicWireMat);
    legL.position.set(-0.24, 0.25, 0);
    const legR = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.09, 1.4, 8), holographicWireMat);
    legR.position.set(0.24, 0.25, 0);
    avatarGroup.add(legL, legR);

    // ── Surrounding Orbital Cyber Rings (围绕多终端的轨道星环) ───────────
    const orbitGroup = new THREE.Group();
    avatarGroup.add(orbitGroup);

    // Ring 1: Inclined Ring
    const ring1Geo = new THREE.TorusGeometry(1.6, 0.012, 16, 100);
    const ring1Mat = new THREE.MeshBasicMaterial({ color: 0x8b5cf6, transparent: true, opacity: 0.4 });
    const ring1 = new THREE.Mesh(ring1Geo, ring1Mat);
    ring1.rotation.x = Math.PI / 2.6;
    ring1.rotation.y = 0.3;
    ring1.position.set(0, 1.8, 0);
    orbitGroup.add(ring1);

    // Ring 2: Wider Horizontal Ring
    const ring2Geo = new THREE.TorusGeometry(2.1, 0.01, 16, 120);
    const ring2Mat = new THREE.MeshBasicMaterial({ color: 0x06b6d4, transparent: true, opacity: 0.35 });
    const ring2 = new THREE.Mesh(ring2Geo, ring2Mat);
    ring2.rotation.x = Math.PI / 2.1;
    ring2.position.set(0, 1.5, 0);
    orbitGroup.add(ring2);

    ringsRef.current = [orbitGroup];

    // Satellites on Ring (representing AI Tools)
    const toolColors = [0xa855f7, 0x3b82f6, 0x10b981, 0xf59e0b, 0xec4899];
    const satellites: THREE.Mesh[] = [];
    for (let i = 0; i < 5; i++) {
      const satGeo = new THREE.SphereGeometry(0.06, 12, 12);
      const satMat = new THREE.MeshBasicMaterial({ color: toolColors[i] });
      const sat = new THREE.Mesh(satGeo, satMat);
      orbitGroup.add(sat);
      satellites.push(sat);
    }

    // ── Particle Field (Ambient Quantum Aura) ───────────────────────────
    const particleCount = 1200;
    const particleGeo = new THREE.BufferGeometry();
    const positions = new Float32Array(particleCount * 3);
    const colors = new Float32Array(particleCount * 3);

    const c1 = new THREE.Color(0x8b5cf6);
    const c2 = new THREE.Color(0x06b6d4);

    for (let i = 0; i < particleCount; i++) {
      const theta = Math.random() * Math.PI * 2;
      const radius = 0.4 + Math.random() * 2.2;
      const y = (Math.random() - 0.2) * 3.4;

      positions[i * 3] = Math.cos(theta) * radius;
      positions[i * 3 + 1] = y;
      positions[i * 3 + 2] = Math.sin(theta) * radius;

      const mixed = c1.clone().lerp(c2, Math.random());
      colors[i * 3] = mixed.r;
      colors[i * 3 + 1] = mixed.g;
      colors[i * 3 + 2] = mixed.b;
    }

    particleGeo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    particleGeo.setAttribute("color", new THREE.BufferAttribute(colors, 3));

    const particleMat = new THREE.PointsMaterial({
      size: 0.024,
      vertexColors: true,
      transparent: true,
      opacity: 0.7,
      blending: THREE.AdditiveBlending,
    });

    const particles = new THREE.Points(particleGeo, particleMat);
    avatarGroup.add(particles);
    particlesRef.current = particles;

    // ── Raycasting for Node Hover/Click ─────────────────────────────────
    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();

    const handlePointerMove = (e: MouseEvent) => {
      const rect = container.getBoundingClientRect();
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((e.clientY - rect.top) / height) * 2 + 1;

      // Parallax effect on avatar
      if (avatarGroupRef.current) {
        avatarGroupRef.current.rotation.y = mouse.x * 0.45;
        avatarGroupRef.current.rotation.x = -mouse.y * 0.18;
      }

      raycaster.setFromCamera(mouse, camera);
      const interactables = Object.values(nodesRef.current);
      const intersects = raycaster.intersectObjects(interactables, false);

      if (intersects.length > 0) {
        const hit = intersects[0].object;
        const dim = hit.userData.dimension as PersonaDimension;
        setHoveredNode(dim);
        container.style.cursor = "pointer";
      } else {
        setHoveredNode(null);
        container.style.cursor = "default";
      }
    };

    const handlePointerClick = (e: MouseEvent) => {
      const rect = container.getBoundingClientRect();
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((e.clientY - rect.top) / height) * 2 + 1;

      raycaster.setFromCamera(mouse, camera);
      const interactables = Object.values(nodesRef.current);
      const intersects = raycaster.intersectObjects(interactables, false);

      if (intersects.length > 0) {
        const hit = intersects[0].object;
        const dim = hit.userData.dimension as PersonaDimension;
        onSelectDimension(dim);
      }
    };

    container.addEventListener("mousemove", handlePointerMove);
    container.addEventListener("click", handlePointerClick);

    // ── Animation Loop ──────────────────────────────────────────────────
    let animId: number;
    let clock = new THREE.Clock();

    const animate = () => {
      animId = requestAnimationFrame(animate);
      const elapsed = clock.getElapsedTime();

      // Idle breathing movement
      if (avatarGroupRef.current) {
        const breath = Math.sin(elapsed * 2.2) * 0.035;
        head.position.y = 2.7 + breath * 0.8;
        chest.position.y = 1.85 + breath;
        brainNode.position.y = 2.72 + breath * 0.8;
        heartNode.position.y = 1.9 + breath;
        heartNode.rotation.y = elapsed * 1.5;
        heartNode.rotation.x = elapsed * 0.8;

        // Auto spin if enabled
        if (isRotating && !mouse.x && !mouse.y) {
          avatarGroupRef.current.rotation.y += 0.003;
        }
      }

      // Rotate orbital rings
      if (orbitGroup) {
        ring1.rotation.z = elapsed * 0.4;
        ring2.rotation.z = -elapsed * 0.25;

        // Satellite positions
        satellites.forEach((sat, idx) => {
          const angle = elapsed * 0.6 + (idx * Math.PI * 2) / 5;
          const r = idx % 2 === 0 ? 1.6 : 2.1;
          sat.position.set(Math.cos(angle) * r, 1.65 + Math.sin(angle * 2) * 0.25, Math.sin(angle) * r);
        });
      }

      // Rotate particle aura
      if (particlesRef.current) {
        particlesRef.current.rotation.y = -elapsed * 0.08;
      }

      // Node pulsing highlights
      Object.entries(nodesRef.current).forEach(([key, node]) => {
        const isActive = activeDimension === key || activeDimension === "all";
        const isHover = hoveredNode === key;
        const scale = isActive ? 1.35 + Math.sin(elapsed * 6) * 0.15 : isHover ? 1.3 : 1.0;
        node.scale.set(scale, scale, scale);
      });

      renderer.render(scene, camera);
    };

    animate();

    // ── Resize Observer ─────────────────────────────────────────────────
    const handleResize = () => {
      if (!container || !renderer || !camera) return;
      const newW = container.clientWidth;
      const newH = container.clientHeight || 520;
      camera.aspect = newW / newH;
      camera.updateProjectionMatrix();
      renderer.setSize(newW, newH);
    };

    const resizeObserver = new ResizeObserver(handleResize);
    resizeObserver.observe(container);

    return () => {
      cancelAnimationFrame(animId);
      resizeObserver.disconnect();
      container.removeEventListener("mousemove", handlePointerMove);
      container.removeEventListener("click", handlePointerClick);
      if (renderer.domElement && container.contains(renderer.domElement)) {
        container.removeChild(renderer.domElement);
      }
      renderer.dispose();
    };
  }, [activeDimension, isRotating, onSelectDimension]);

  return (
    <div
      style={{
        position: "relative",
        width: "100%",
        minHeight: 520,
        height: 540,
        borderRadius: 24,
        background: "radial-gradient(ellipse 90% 90% at 50% 20%, rgba(124, 58, 237, 0.18) 0%, rgba(15, 15, 26, 0.85) 60%, rgba(8, 8, 14, 0.98) 100%)",
        border: "1px solid rgba(139, 92, 246, 0.28)",
        boxShadow: "0 24px 64px -16px rgba(0, 0, 0, 0.6), inset 0 1px 1px rgba(255, 255, 255, 0.1)",
        overflow: "hidden",
        backdropFilter: "blur(24px)",
      }}
    >
      {/* 3D Canvas Canvas Mount Container */}
      <div ref={containerRef} style={{ width: "100%", height: "100%" }} />

      {/* Top Holographic Status Bar */}
      <div
        style={{
          position: "absolute",
          top: 18,
          left: 20,
          right: 20,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          pointerEvents: "none",
          zIndex: 10,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <div
            style={{
              padding: "5px 12px",
              borderRadius: 9999,
              background: "rgba(124, 58, 237, 0.25)",
              border: "1px solid rgba(168, 85, 247, 0.4)",
              backdropFilter: "blur(12px)",
              display: "flex",
              alignItems: "center",
              gap: 8,
              fontSize: 12,
              fontWeight: 600,
              color: "#c084fc",
              boxShadow: "0 0 16px rgba(168, 85, 247, 0.3)",
            }}
          >
            <span
              style={{
                width: 7,
                height: 7,
                borderRadius: 9999,
                background: "#22c55e",
                boxShadow: "0 0 8px #22c55e",
              }}
            />
            <span>DIGITAL TWIN · 全息数字孪生中枢</span>
          </div>

          <span style={{ fontSize: 11, color: "var(--aurora-fg4)" }}>
            鼠标悬停/移动探索神经交互锚点
          </span>
        </div>

        {/* View mode actions */}
        <div style={{ pointerEvents: "auto", display: "flex", alignItems: "center", gap: 6 }}>
          <button
            type="button"
            onClick={() => onSelectDimension("all")}
            style={{
              padding: "4px 10px",
              borderRadius: 8,
              fontSize: 11,
              fontWeight: activeDimension === "all" ? 600 : 450,
              background: activeDimension === "all" ? "var(--aurora-accent)" : "rgba(255,255,255,0.06)",
              color: activeDimension === "all" ? "#fff" : "var(--aurora-fg3)",
              border: "1px solid var(--aurora-border)",
              cursor: "pointer",
            }}
          >
            全览态
          </button>
          <button
            type="button"
            onClick={() => setIsRotating((v) => !v)}
            style={{
              padding: "4px 10px",
              borderRadius: 8,
              fontSize: 11,
              background: isRotating ? "rgba(124, 58, 237, 0.2)" : "rgba(255,255,255,0.06)",
              color: isRotating ? "var(--aurora-accent)" : "var(--aurora-fg3)",
              border: "1px solid var(--aurora-border)",
              cursor: "pointer",
            }}
            title={isRotating ? "暂停自转" : "开启自转"}
          >
            {isRotating ? "自转中" : "已固定"}
          </button>
        </div>
      </div>

      {/* Floating 4-Dimension Neural Anchors Overlay (点击直通各维度) */}
      <div
        style={{
          position: "absolute",
          bottom: 18,
          left: 18,
          right: 18,
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(130px, 1fr))",
          gap: 10,
          zIndex: 10,
        }}
      >
        {/* Brain: 铁律与红线 */}
        <DimensionCard
          title="认知与铁律"
          subtitle="头脑神经核"
          color="#a855f7"
          icon="🧠"
          count={ruleStats.ironLaws}
          active={activeDimension === "brain"}
          onClick={() => onSelectDimension("brain")}
        />

        {/* Communication: 沟通风格 */}
        <DimensionCard
          title="沟通与应答"
          subtitle="咽喉共振点"
          color="#06b6d4"
          icon="💬"
          count={ruleStats.communication}
          active={activeDimension === "communication"}
          onClick={() => onSelectDimension("communication")}
        />

        {/* Tech: 架构与技术偏好 */}
        <DimensionCard
          title="架构与技术"
          subtitle="核心动力源"
          color="#f59e0b"
          icon="⚡"
          count={ruleStats.tech}
          active={activeDimension === "tech"}
          onClick={() => onSelectDimension("tech")}
        />

        {/* Execution: 工作方式与流程 */}
        <DimensionCard
          title="执行与工作流"
          subtitle="四肢执行端"
          color="#10b981"
          icon="🛠️"
          count={ruleStats.execution}
          active={activeDimension === "execution"}
          onClick={() => onSelectDimension("execution")}
        />
      </div>
    </div>
  );
}

function DimensionCard({
  title,
  subtitle,
  color,
  icon,
  count,
  active,
  onClick,
}: {
  title: string;
  subtitle: string;
  color: string;
  icon: string;
  count: number;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: "10px 14px",
        borderRadius: 14,
        background: active
          ? `linear-gradient(135deg, ${color}28, ${color}10)`
          : "rgba(18, 18, 28, 0.75)",
        border: active
          ? `1.5px solid ${color}`
          : "1px solid rgba(255, 255, 255, 0.08)",
        boxShadow: active ? `0 8px 24px -4px ${color}40` : "0 4px 12px rgba(0,0,0,0.25)",
        backdropFilter: "blur(16px)",
        color: "#fff",
        cursor: "pointer",
        textAlign: "left",
        transition: "all 0.2s cubic-bezier(0.16, 1, 0.3, 1)",
        transform: active ? "translateY(-2px)" : "none",
        outline: "none",
      }}
    >
      <div
        style={{
          width: 34,
          height: 34,
          borderRadius: 10,
          background: `${color}20`,
          border: `1px solid ${color}40`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 16,
          flexShrink: 0,
        }}
      >
        {icon}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 4 }}>
          <div
            style={{
              fontSize: 12.5,
              fontWeight: 600,
              color: active ? color : "var(--aurora-fg1)",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {title}
          </div>
          <span
            style={{
              fontSize: 10,
              fontWeight: 700,
              padding: "1px 5px",
              borderRadius: 6,
              background: `${color}25`,
              color: color,
            }}
          >
            {count}
          </span>
        </div>
        <div style={{ fontSize: 10.5, color: "var(--aurora-fg4)", marginTop: 2 }}>{subtitle}</div>
      </div>
    </button>
  );
}
