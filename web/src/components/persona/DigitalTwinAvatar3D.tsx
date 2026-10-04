"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";

export type PersonaDimension = "brain" | "communication" | "tech" | "execution" | "project" | "all";

interface DigitalTwinAvatar3DProps {
  activeDimension: PersonaDimension;
  onSelectDimension: (dim: PersonaDimension) => void;
  ruleStats?: {
    ironLaws: number;
    communication: number;
    tech: number;
    execution: number;
    project: number;
  };
  className?: string;
}

export default function DigitalTwinAvatar3D({
  activeDimension,
  onSelectDimension,
  ruleStats = { ironLaws: 11, communication: 6, tech: 15, execution: 13, project: 5 },
  className = "",
}: DigitalTwinAvatar3DProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [hoveredNode, setHoveredNode] = useState<PersonaDimension | null>(null);
  const [isRotating, setIsRotating] = useState(true);

  // References
  const sceneRef = useRef<THREE.Scene | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const avatarGroupRef = useRef<THREE.Group | null>(null);
  const organMeshesRef = useRef<Record<string, THREE.Mesh>>({});
  const ringGroupRef = useRef<THREE.Group | null>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const width = container.clientWidth || 800;
    const height = container.clientHeight || 380;

    // 1. Scene & Camera Setup (Clean Portrait Perspective)
    const scene = new THREE.Scene();
    sceneRef.current = scene;

    const camera = new THREE.PerspectiveCamera(40, width / height, 0.1, 100);
    camera.position.set(0, 1.25, 4.4);

    // 2. High-Performance WebGL Renderer
    const renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: true,
      powerPreference: "high-performance",
    });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.3;
    container.appendChild(renderer.domElement);
    rendererRef.current = renderer;

    // 3. Studio Cyber Atmosphere Lights
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.9);
    scene.add(ambientLight);

    const purpleLight = new THREE.PointLight(0xa855f7, 2.8, 10);
    purpleLight.position.set(-2.5, 2.5, 2);
    scene.add(purpleLight);

    const cyanLight = new THREE.PointLight(0x06b6d4, 2.5, 10);
    cyanLight.position.set(2.5, 1.0, 2);
    scene.add(cyanLight);

    const topLight = new THREE.DirectionalLight(0xffffff, 1.4);
    topLight.position.set(0, 4.5, 3);
    scene.add(topLight);

    // 4. Holographic Synthetic Humanoid Assembly (Clean, Modern, Crystal Cyberpunk)
    const avatarGroup = new THREE.Group();
    avatarGroup.position.set(0, -0.65, 0);
    avatarGroupRef.current = avatarGroup;
    scene.add(avatarGroup);

    // Wireframe & Crystal Materials
    const crystalMat = new THREE.MeshStandardMaterial({
      color: 0x8b5cf6,
      wireframe: true,
      transparent: true,
      opacity: 0.35,
      roughness: 0.2,
      metalness: 0.8,
    });

    const innerGlowMat = new THREE.MeshStandardMaterial({
      color: 0x3b82f6,
      transparent: true,
      opacity: 0.45,
      roughness: 0.2,
      metalness: 0.9,
    });

    // Organ Node Glow Materials
    const nodeMaterials = {
      brain: new THREE.MeshStandardMaterial({
        color: 0xef4444,
        emissive: 0xef4444,
        emissiveIntensity: 2.2,
        roughness: 0.1,
      }),
      communication: new THREE.MeshStandardMaterial({
        color: 0x06b6d4,
        emissive: 0x06b6d4,
        emissiveIntensity: 2.2,
        roughness: 0.1,
      }),
      tech: new THREE.MeshStandardMaterial({
        color: 0xf59e0b,
        emissive: 0xf59e0b,
        emissiveIntensity: 2.2,
        roughness: 0.1,
      }),
      execution: new THREE.MeshStandardMaterial({
        color: 0x10b981,
        emissive: 0x10b981,
        emissiveIntensity: 2.2,
        roughness: 0.1,
      }),
    };

    // --- Anatomical Humanoid Mesh Construction ---
    // 1. Head (Sculpted Icosahedral Facets)
    const headGeo = new THREE.IcosahedronGeometry(0.34, 2);
    const headMesh = new THREE.Mesh(headGeo, crystalMat);
    headMesh.position.set(0, 2.58, 0);
    avatarGroup.add(headMesh);

    // Brain Core (Inside upper skull)
    const brainCoreGeo = new THREE.SphereGeometry(0.12, 16, 16);
    const brainCore = new THREE.Mesh(brainCoreGeo, nodeMaterials.brain);
    brainCore.position.set(0, 2.68, 0);
    brainCore.userData = { dimension: "brain" };
    avatarGroup.add(brainCore);
    organMeshesRef.current.brain = brainCore;

    // Head Halo Ring (Floating wisdom crown)
    const haloGeo = new THREE.TorusGeometry(0.24, 0.008, 16, 48);
    const haloMat = new THREE.MeshBasicMaterial({ color: 0xef4444, transparent: true, opacity: 0.8 });
    const halo = new THREE.Mesh(haloGeo, haloMat);
    halo.rotation.x = Math.PI / 2.2;
    halo.position.set(0, 2.92, 0);
    avatarGroup.add(halo);

    // 2. Neck & Vocal Node (Communication)
    const neckGeo = new THREE.CylinderGeometry(0.12, 0.15, 0.24, 12);
    const neck = new THREE.Mesh(neckGeo, innerGlowMat);
    neck.position.set(0, 2.24, 0);
    avatarGroup.add(neck);

    const vocalNodeGeo = new THREE.SphereGeometry(0.07, 16, 16);
    const vocalNode = new THREE.Mesh(vocalNodeGeo, nodeMaterials.communication);
    vocalNode.position.set(0, 2.24, 0.12);
    vocalNode.userData = { dimension: "communication" };
    avatarGroup.add(vocalNode);
    organMeshesRef.current.communication = vocalNode;

    // 3. Chest & Tech Core (Architecture & Tech)
    const chestGeo = new THREE.CylinderGeometry(0.42, 0.32, 0.65, 16);
    const chest = new THREE.Mesh(chestGeo, crystalMat);
    chest.position.set(0, 1.8, 0);
    avatarGroup.add(chest);

    const techCoreGeo = new THREE.OctahedronGeometry(0.14, 1);
    const techCore = new THREE.Mesh(techCoreGeo, nodeMaterials.tech);
    techCore.position.set(0, 1.84, 0.1);
    techCore.userData = { dimension: "tech" };
    avatarGroup.add(techCore);
    organMeshesRef.current.tech = techCore;

    // 4. Spine & Pelvis
    const spineGeo = new THREE.CylinderGeometry(0.26, 0.32, 0.45, 12);
    const spine = new THREE.Mesh(spineGeo, innerGlowMat);
    spine.position.set(0, 1.3, 0);
    avatarGroup.add(spine);

    const pelvisGeo = new THREE.CylinderGeometry(0.34, 0.28, 0.3, 12);
    const pelvis = new THREE.Mesh(pelvisGeo, crystalMat);
    pelvis.position.set(0, 0.98, 0);
    avatarGroup.add(pelvis);

    // 5. Arms & Execution Hands
    const armL = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.06, 0.85, 8), crystalMat);
    armL.position.set(-0.68, 1.58, 0.02);
    armL.rotation.z = 0.22;
    const armR = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.06, 0.85, 8), crystalMat);
    armR.position.set(0.68, 1.58, 0.02);
    armR.rotation.z = -0.22;
    avatarGroup.add(armL, armR);

    const handNodeGeo = new THREE.SphereGeometry(0.09, 16, 16);
    const handL = new THREE.Mesh(handNodeGeo, nodeMaterials.execution);
    handL.position.set(-0.8, 1.15, 0.08);
    handL.userData = { dimension: "execution" };
    const handR = new THREE.Mesh(handNodeGeo, nodeMaterials.execution);
    handR.position.set(0.8, 1.15, 0.08);
    handR.userData = { dimension: "execution" };
    avatarGroup.add(handL, handR);
    organMeshesRef.current.execution = handR;

    // 6. Legs
    const legL = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.07, 1.25, 8), crystalMat);
    legL.position.set(-0.2, 0.32, 0);
    const legR = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.07, 1.25, 8), crystalMat);
    legR.position.set(0.2, 0.32, 0);
    avatarGroup.add(legL, legR);

    // 7. Surrounding AI Terminal Orbital Rings (Claude Code / Antigravity / Codex / OpenClaw / Hermes)
    const ringGroup = new THREE.Group();
    avatarGroup.add(ringGroup);
    ringGroupRef.current = ringGroup;

    const ring1 = new THREE.Mesh(
      new THREE.TorusGeometry(1.4, 0.008, 16, 80),
      new THREE.MeshBasicMaterial({ color: 0x8b5cf6, transparent: true, opacity: 0.35 })
    );
    ring1.rotation.x = Math.PI / 2.5;
    ring1.position.set(0, 1.75, 0);
    ringGroup.add(ring1);

    const ring2 = new THREE.Mesh(
      new THREE.TorusGeometry(1.85, 0.006, 16, 100),
      new THREE.MeshBasicMaterial({ color: 0x06b6d4, transparent: true, opacity: 0.3 })
    );
    ring2.rotation.x = Math.PI / 2.1;
    ring2.position.set(0, 1.5, 0);
    ringGroup.add(ring2);

    // 5 Orbiting AI Terminal Satellites
    const toolColors = [0xa855f7, 0x3b82f6, 0x10b981, 0xf59e0b, 0xec4899];
    const satellites: THREE.Mesh[] = [];
    for (let i = 0; i < 5; i++) {
      const sat = new THREE.Mesh(
        new THREE.SphereGeometry(0.045, 12, 12),
        new THREE.MeshBasicMaterial({ color: toolColors[i] })
      );
      ringGroup.add(sat);
      satellites.push(sat);
    }

    // 8. Quantum Ambient Particle Cloud (Pure GPU Animation)
    const particleCount = 300;
    const particleGeo = new THREE.BufferGeometry();
    const particlePositions = new Float32Array(particleCount * 3);
    for (let i = 0; i < particleCount * 3; i += 3) {
      particlePositions[i] = (Math.random() - 0.5) * 3.8;
      particlePositions[i + 1] = Math.random() * 3.2;
      particlePositions[i + 2] = (Math.random() - 0.5) * 3.8;
    }
    particleGeo.setAttribute("position", new THREE.BufferAttribute(particlePositions, 3));
    const particles = new THREE.Points(
      particleGeo,
      new THREE.PointsMaterial({
        color: 0xa855f7,
        size: 0.02,
        transparent: true,
        opacity: 0.45,
        blending: THREE.AdditiveBlending,
      })
    );
    avatarGroup.add(particles);

    // 9. Interactive Raycasting & Drag Rotation
    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();
    let isDragging = false;
    let prevMouseX = 0;

    const handlePointerDown = (e: MouseEvent) => {
      isDragging = true;
      prevMouseX = e.clientX;
    };

    const handlePointerUp = () => {
      isDragging = false;
    };

    const handlePointerMove = (e: MouseEvent) => {
      const rect = container.getBoundingClientRect();
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

      if (isDragging) {
        const deltaX = e.clientX - prevMouseX;
        avatarGroup.rotation.y += deltaX * 0.008;
        prevMouseX = e.clientX;
      }

      // Parallax Head Rotation
      headMesh.rotation.y = THREE.MathUtils.lerp(headMesh.rotation.y, mouse.x * 0.25, 0.05);
      headMesh.rotation.x = THREE.MathUtils.lerp(headMesh.rotation.x, -mouse.y * 0.15, 0.05);

      // Raycast detection
      raycaster.setFromCamera(mouse, camera);
      const targets = Object.values(organMeshesRef.current);
      const intersects = raycaster.intersectObjects(targets);
      if (intersects.length > 0) {
        const dim = intersects[0].object.userData?.dimension as PersonaDimension;
        setHoveredNode(dim || null);
        container.style.cursor = "pointer";
      } else {
        setHoveredNode(null);
        container.style.cursor = isDragging ? "grabbing" : "grab";
      }
    };

    const handlePointerClick = (e: MouseEvent) => {
      const rect = container.getBoundingClientRect();
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

      raycaster.setFromCamera(mouse, camera);
      const targets = Object.values(organMeshesRef.current);
      const intersects = raycaster.intersectObjects(targets);
      if (intersects.length > 0) {
        const dim = intersects[0].object.userData?.dimension as PersonaDimension;
        if (dim) {
          onSelectDimension(dim);
        }
      }
    };

    container.addEventListener("mousedown", handlePointerDown);
    window.addEventListener("mouseup", handlePointerUp);
    container.addEventListener("mousemove", handlePointerMove);
    container.addEventListener("click", handlePointerClick);

    // 10. Smooth 60fps Animation Loop (Pure GPU & Transforms, No React State In Loop!)
    let animId: number;
    const clock = new THREE.Clock();

    const animate = () => {
      animId = requestAnimationFrame(animate);
      const elapsed = clock.getElapsedTime();

      // Gentle natural breathing motion (Chest expansion & elevation)
      chestMeshScale(elapsed);
      particles.rotation.y = elapsed * 0.02;

      // Auto rotation if user enables it
      if (isRotating) {
        avatarGroup.rotation.y += 0.004;
      }

      // Orbit satellites around ring
      satellites.forEach((sat, idx) => {
        const angle = elapsed * 0.6 + (idx * Math.PI * 2) / 5;
        sat.position.set(Math.cos(angle) * 1.85, 1.5 + Math.sin(angle * 2) * 0.1, Math.sin(angle) * 1.85);
      });

      // Halo breathing & rotation
      halo.rotation.z = elapsed * 0.4;
      halo.scale.setScalar(1 + Math.sin(elapsed * 2) * 0.06);

      // Pulse organ nodes
      Object.entries(organMeshesRef.current).forEach(([key, node]) => {
        const isSelected = activeDimension === key || activeDimension === "all";
        const isHover = hoveredNode === key;
        const scale = isSelected ? 1.3 + Math.sin(elapsed * 4) * 0.15 : isHover ? 1.25 : 1.0;
        node.scale.set(scale, scale, scale);

        if (key === "tech") {
          node.rotation.x = elapsed * 1.2;
          node.rotation.y = elapsed * 1.6;
        }
      });

      renderer.render(scene, camera);
    };

    function chestMeshScale(time: number) {
      const breath = 1 + Math.sin(time * 1.8) * 0.02;
      chest.scale.set(breath, breath, breath);
    }

    animate();

    // 11. Resize Observer
    const handleResize = () => {
      if (!container || !renderer || !camera) return;
      const newW = container.clientWidth;
      const newH = container.clientHeight;
      camera.aspect = newW / newH;
      camera.updateProjectionMatrix();
      renderer.setSize(newW, newH);
    };

    const resizeObserver = new ResizeObserver(handleResize);
    resizeObserver.observe(container);

    return () => {
      cancelAnimationFrame(animId);
      resizeObserver.disconnect();
      container.removeEventListener("mousedown", handlePointerDown);
      window.removeEventListener("mouseup", handlePointerUp);
      container.removeEventListener("mousemove", handlePointerMove);
      container.removeEventListener("click", handlePointerClick);
      if (renderer.domElement && container.contains(renderer.domElement)) {
        container.removeChild(renderer.domElement);
      }
      renderer.dispose();
    };
  }, [activeDimension, isRotating, onSelectDimension]);

  const DIMENSIONS_DATA = [
    {
      id: "brain" as const,
      label: "🧠 脑核 · 绝对红线",
      color: "#EF4444",
      count: ruleStats.ironLaws,
      desc: "严守红线、禁止凭猜硬编码、不盲目回滚",
    },
    {
      id: "communication" as const,
      label: "💬 喉核 · 交互与沟通",
      color: "#06B6D4",
      count: ruleStats.communication,
      desc: "始终中文、直给结论、无废话、1)2)3)编号",
    },
    {
      id: "tech" as const,
      label: "⚡ 心核 · 架构与技术偏好",
      color: "#F59E0B",
      count: ruleStats.tech,
      desc: "性能流式、容器化K8s、本地优先、高并发",
    },
    {
      id: "execution" as const,
      label: "🛠️ 肢端 · 工作与执行习惯",
      color: "#10B981",
      count: ruleStats.execution,
      desc: "自主推进做完、数据校验闭环、重复任务自动化",
    },
    {
      id: "project" as const,
      label: "🎯 靶向 · 项目专属规范",
      color: "#8B5CF6",
      count: ruleStats.project,
      desc: "memento 约定、Conventional Commits、Cargo.lock",
    },
  ];

  return (
    <div
      className={`relative w-full h-full min-h-[380px] rounded-3xl overflow-hidden select-none border border-[var(--aurora-border)] bg-gradient-to-b from-[#090b14] via-[#06070d] to-[#040508] shadow-xl ${className}`}
    >
      {/* 3D WebGL Canvas */}
      <div ref={containerRef} className="w-full h-full cursor-grab active:cursor-grabbing" />

      {/* Top Floating Glass Header */}
      <div className="absolute top-3.5 left-4 right-4 flex items-center justify-between pointer-events-none z-10">
        <div className="flex items-center gap-2 bg-black/40 backdrop-blur-md px-3 py-1.5 rounded-full border border-white/10 shadow-lg">
          <div className="w-2 h-2 rounded-full bg-[#10B981] animate-ping" />
          <span className="text-[11px] font-mono text-white/90 font-medium tracking-wide">
            HOLOGRAPHIC SYNTHETIC TWIN · 60 FPS
          </span>
        </div>

        <div className="flex items-center gap-2 pointer-events-auto">
          {/* Rotation Toggle */}
          <button
            onClick={() => setIsRotating((v) => !v)}
            className={`px-3 py-1 rounded-xl text-[11px] font-mono font-medium transition-all backdrop-blur-md border ${
              isRotating
                ? "bg-[#A855F7]/25 text-[#A855F7] border-[#A855F7]/50"
                : "bg-black/40 text-white/70 border-white/10 hover:bg-black/60"
            }`}
          >
            {isRotating ? "全息自转中" : "暂停旋转"}
          </button>
        </div>
      </div>

      {/* Bottom Holographic Dimension Pills Bar */}
      <div className="absolute bottom-3 left-3 right-3 flex items-center justify-center gap-2 z-20 pointer-events-auto overflow-x-auto scrollbar-none py-1">
        <button
          onClick={() => onSelectDimension("all")}
          className={`px-3.5 py-1.5 rounded-xl text-xs font-medium transition-all shrink-0 backdrop-blur-md border ${
            activeDimension === "all"
              ? "bg-[#8B5CF6] text-white border-[#8B5CF6] shadow-lg font-semibold"
              : "bg-black/60 text-white/70 border-white/10 hover:text-white hover:bg-black/80"
          }`}
        >
          🌐 全景视野
        </button>

        {DIMENSIONS_DATA.map((dim) => {
          const isSelected = activeDimension === dim.id;
          return (
            <button
              key={dim.id}
              onClick={() => onSelectDimension(dim.id)}
              className={`px-3 py-1.5 rounded-xl text-xs font-medium transition-all shrink-0 backdrop-blur-md border flex items-center gap-1.5 ${
                isSelected
                  ? "text-white shadow-lg font-semibold scale-102"
                  : "bg-black/60 text-white/70 border-white/10 hover:text-white hover:bg-black/80"
              }`}
              style={{
                backgroundColor: isSelected ? dim.color : undefined,
                borderColor: isSelected ? dim.color : undefined,
              }}
            >
              <span>{dim.label.split(" · ")[0]}</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-black/30 font-mono font-bold">
                {dim.count}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
